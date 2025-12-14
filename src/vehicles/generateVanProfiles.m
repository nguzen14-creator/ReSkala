function profiles = generateVanProfiles(N, segmentFile, chargingTypesFile, fid)
%GENERATEVANPROFILES  Generate N van mobility profiles and print to file/screen.
%   profiles = generateVanProfiles(N, segmentFile, chargingTypesFile, fid)
%   Reads segmentFile ('ev_segments.csv') and chargingTypesFile ('chargingCompatible.csv')
%   Outputs formatted profiles for workday/weekend to file (fid) and screen.
%   Each simulation includes both Workday and Weekend trip profiles with realistic logic.

  % --- Read segment (vehicle specs) and charging compatibility data
  Tseg   = readEVsegment(segmentFile);
  Ctypes = readChargingCompatible(chargingTypesFile);
  
  % --- Read temperature effect table, preserving original column names
  opts = detectImportOptions('Temperatur.CSV', 'Delimiter', ',');
  opts.VariableNamingRule = 'preserve';
  T = readtable('Temperatur.CSV', opts);

  % --- Get the full operating temperature range
  overallMin = min(T.Temp_from);
  overallMax = max(T.Temp_to);

  % --- Identify which row corresponds to 'Van' in vehicle specs
  idx = strcmp(Tseg.Segment, 'Van');
  capMin = Tseg.NomCap_min(idx);
  capMax = Tseg.NomCap_max(idx);
  rangeMin = Tseg.Range_min(idx);
  rangeMax = Tseg.Range_max(idx);
  
  % --- Get average speeds for urban, rural, highway for Van
  v_urban = Tseg.AvgSpd_urban(idx);
  v_rural = Tseg.AvgSpd_rural(idx);
  v_high  = Tseg.AvgSpd_highway(idx);

  % --- Find compatible charger types for Van (AC/DC, various kW)
  locations = ["Public", "Private"];
  VanRow = Ctypes(strcmp(Ctypes.Segment,'Van'), :);
  vars = Ctypes.Properties.VariableNames(2:end);
  compatible = vars(VanRow{1,2:end}');  

  % --- Prepare an empty template struct for output profiles
  F = struct( ...
    'Purpose', [], 'Day', [], 'Temperature', [], 'Consumption', [], 'FullCapacity', [], ...
    'CapacityWithTemperatur', [], 'PercentOperatingCapacity', [], 'FullRange', [], ...
    'RangeWithTemperatur', [], 'PercentOperatingRange', [], 'Distance', [], 'AvgSpeed', [], ...
    'ChargingLocation', [], 'ChargingType', [], 'SoC', [], 'PercentChargingLoss', [], ...
    'TripNumber', [], 'TripStart', [], 'TripEnd', [], 'RunTime', [], 'StopTime', [], ...
    'ChargeOnRoad', [], 'ChargingTimeOnRoad', [], 'BatteryPerc', [], 'TotalTimeToCharge', [] );
  profiles = repmat(F, N, 2);  % Preallocate for speed (not used for output in this version)

  for i = 1:N
    % --- Draw a random operating temperature for this simulation
    tempRandom = overallMin + (overallMax - overallMin)*rand();
    idxLogical = (T.Temp_from <= tempRandom) & (tempRandom <= T.Temp_to);
    idxRow = find(idxLogical, 1, 'first');
    if isempty(idxRow)
      error("No range found for temperature %.2f!", tempRandom);
    end

    % --- Get the range of active capacity/range at this temperature
    capMinTemp   = T.Capacity_min(idxRow);
    capMaxTemp   = T.Capacity_max(idxRow);
    rangeMinTemp = T.Range_min(idxRow);
    rangeMaxTemp = T.Range_max(idxRow);
    % --- Randomize the % of usable capacity and range for temperature
    capTemp      = capMinTemp + (capMaxTemp - capMinTemp)*rand();
    rangeTemp    = rangeMinTemp + (rangeMaxTemp - rangeMinTemp)*rand();

    % --- Draw random full battery capacity/range within van's possible values
    capFull   = capMin   + (capMax   - capMin)   * rand;
    rangeFull = rangeMin + (rangeMax - rangeMin) * rand;
    % --- Calculate energy consumption in Wh/km (capacity divided by range)
    use = (capFull*1000) / rangeFull;

    % --- Adjust for temperature: actual available cap/range
    cap   = capFull   * capTemp   / 100;
    range = rangeFull * rangeTemp / 100;

    % --- Randomly select a compatible charging type for this van
    ctype = compatible{ randi(numel(compatible)) };
    % --- Extract numeric power value from charger string (handles decimals)
    pwr = str2double(regexp(ctype,'\d+(\.\d+)?','match','once'));
    % --- Randomly change 7.4 kW AC chargers to 11 kW for diversity
    if abs(pwr - 7.4) < 1e-6
      if rand() < 0.5
        pwr = 7.4;
      else
        pwr = 11;
      end
    end
    % --- Set charging location and target SoC depending on AC/DC type
    if startsWith(ctype,'DC')
      loc = 'Public';
      SOC = 80;
    elseif startsWith(ctype,'AC')
      loc = locations(randi(2)); % Randomly public/private
      SOC = 100;
    else
      loc = 'Private';
      SOC = 100;
    end

    purpose = 'Van'; % Set purpose string

    % --- Select one of 3 distance bins: <100 km, 100-299 km, >=300 km
    r = rand();
    if     r < 0.20
      distBin = 1;   % 20% chance for <100 km
    elseif r < 0.20+0.60
      distBin = 2;   % 60% chance for 100-299 km
    else
      distBin = 3;   % 20% chance for >=300 km
    end

    % --- Prepare empty struct for each day (will hold results)
    P = struct();

    days = {'Workday','Weekend'};
    for d = 1:2
      day = days{d};

      % --- Set trip window and duration rules for Workday/Weekend
      if d==1
        startWin       = [4, 15];      % Possible first trip start window (4:00–15:00)
        dur1Range      = [0.1, 2.5];   % Duration of first trip in hours
        stop1Range     = [0.1, 1.5];   % First trip stop duration
        durOtherRange  = [0.1, 2.5];   % Duration of other trips
        stopOtherRange = [0.1, 1.5];   % Stop between other trips
      else
        startWin       = [6, 12];      % Possible first trip start window (6:00–12:00)
        dur1Range      = [0.1, 2];
        stop1Range     = [0.1, 1.5];
        durOtherRange  = [0.1, 2];
        stopOtherRange = [0.1, 1.5];
      end

        % --- Pick number of trips for the day: 2 to 4 (inclusive)
        Ntrip = randi([2,4]);
        
        valid = false;  % Will be set to true once all constraints for the day's trips are satisfied
        while ~valid
            % --- Randomize the first trip's parameters:
            %   - start1: random start hour in the allowed window (e.g. 4-15 for weekday, 6-12 for weekend)
            %   - dur1:   random duration of first trip (within trip duration range for day type)
            %   - stop1:  random stop time after first trip (within stop time range for day type)
            start1 = startWin(1) + diff(startWin)*rand();            % First trip start time
            dur1   = dur1Range(1) + diff(dur1Range)*rand();          % First trip duration
            stop1  = stop1Range(1) + diff(stop1Range)*rand();        % First trip stop
        
            % --- Arrays to hold all trip start/end/duration/stop times
            starts = zeros(1,Ntrip); ends = zeros(1,Ntrip);
            durs   = zeros(1,Ntrip); stops = zeros(1,Ntrip);
        
            % --- Set the first trip's timing
            starts(1)= start1; 
            ends(1)= start1+dur1;
            durs(1)= dur1; 
            stops(1)= stop1;
        
            % --- Generate all following trips in sequence, using random durations and stops
            for t = 2:Ntrip
                starts(t) = ends(t-1) + stops(t-1);                           % Next trip starts after previous ends plus stop
                durs(t)   = durOtherRange(1) + diff(durOtherRange)*rand();    % Random duration for this trip
                stops(t)  = stopOtherRange(1) + diff(stopOtherRange)*rand();  % Random stop after this trip
                ends(t)   = starts(t) + durs(t);                              % Trip ends after its duration
            end
        
            % --- CONSTRAINTS SECTION ---
            %   - All trips for this day must obey several rules.
            % 1. The final trip must end before midnight (i.e., no wrap to next day)
            if ends(end) > 24
                continue  % Not valid; try again with new randomization
            end
        
            % 2. The sum of all stop times between trips must be at least 1 hour and at most 3 hours
            totalStop = sum(stops);
            if totalStop < 1 || totalStop > 3
                continue  % Not valid; try again
            end
        
            % 3. The total window from first trip's start to last trip's end must be between 4 and 10 hours
            window = ends(end) - starts(1);
            if window < 4 || window > 10
                continue  % Not valid; try again
            end
        
            % --- Calculate total running/driving time (sum of all trip durations)
            runT = sum(durs);
        
            % --- Randomize the distribution of time spent on road types (urban, rural, highway):
            fracUrban   = 44 + (rand*10 - 5);           % Urban: 44% ±5%
            fracRural   = 27 + (rand*10 - 5);           % Rural: 27% ±5%
            fracHighway = 100 - fracUrban - fracRural;  % Highway: rest to make 100%
        
            % --- Calculate distances for each road type, using average segment speeds for each
            highDist  = v_urban * runT * fracUrban/100;      % Highway distance = highway speed × total time × fraction
            ruralDist = v_rural * runT * fracRural/100;      % Rural distance = rural speed × total time × fraction
            urbanDist = v_high  * runT * fracHighway/100;    % Urban distance = urban speed × total time × fraction
        
            % --- Sum total distance driven in all trips
            totalDist = highDist + ruralDist + urbanDist;
        
            % --- Enforce the *distance bin* (randomly picked earlier) for this day:
            %    Bin 1:   <100 km
            %    Bin 2: 100–299 km
            %    Bin 3: ≥300 km
            switch distBin
                case 1
                    if totalDist >= 100, continue; end    % Retry if too long for this bin
                case 2
                    if totalDist < 100 || totalDist >= 300, continue; end  % Retry if outside range
                case 3
                    if totalDist < 300, continue; end     % Retry if not enough for bin 3
            end
        
            valid = true; % If all constraints passed, accept this day's trips and break out of loop
        end
        
        % --- At this point, all trips are valid for this day ---
        
        % --- Format trip times into human-readable strings for display/storage
        startStr = arrayfun(@(x) sprintf('%dh %02dmin',floor(x),round(mod(x,1)*60)),starts,'Uni',false);
        endStr   = arrayfun(@(x) sprintf('%dh %02dmin',floor(x),round(mod(x,1)*60)),ends,  'Uni',false);
        stopStr  = arrayfun(@(x) sprintf('%dh %02dmin',floor(x),round(mod(x,1)*60)),stops, 'Uni',false);
        
        % --- Calculate average trip speed (overall): total distance / total driving time
        avgspeed = totalDist / runT;
        
        % --- Compute energy usage for the day: usage (Wh/km) × distance (km)
        usedWh = use * totalDist;
        remPerc = max(0,(cap*1000 - usedWh)/(cap*1000)*100);  % Battery remaining at end, as percentage
        
        % --- Randomize charging loss for this day (DC: 6-8%, AC: 5-10%)
        charlossDC = 6 + (8 - 6)*rand;
        charlossAC = 5 + (10 - 5)*rand;
        if remPerc < 80
            % If battery drops below 80%, assign a charging loss
            if startsWith(ctype,'DC')
                charloss = charlossDC;
            else
                charloss = charlossAC;
            end
        else
            charloss = 0;   % Otherwise, no charging loss (no charging needed)
        end
        
        % --- Calculate how much energy (in kWh) was used during the day
        usedCap = (use * totalDist)/1000;
        
        % --- Determine if on-road charging is needed today:
        if totalDist < (range - 20)
            % -- If the day's trips fit within the available range minus buffer (20 km)
            remPerc = round((capFull - usedCap - capFull * (100-capTemp)/100)*100 / capFull); % Final SoC as %
            chgRoad = 'No';      % No on-road charging required
            timeRoad = 0.0;      % No time spent on-road charging
        
            if remPerc < 80
                % If battery falls below 80%, calculate charge time needed to refill to target SoC (usually at home)
                currentWh = capFull * (remPerc/100);          % Energy left in battery at day's end
                targetWh  = capFull * (SOC/100);              % Target SoC (80% or 100%)
                energyToCharge = targetWh - currentWh;        % Energy that must be recharged
                timeToFull = energyToCharge * (1 + charloss/100) / pwr;  % Time needed, including losses
            else
                timeToFull = 0.0;    % If battery above 80%, no charge needed
            end
        else
            % -- If today's trips exceed the safe range, force at least one on-road charge session
            remPerc    = '';     % Leave remaining battery blank (unknown after charging event)
            % Randomly pick one of four charging powers for road charging (simulates variable infrastructure)
            pwrChoices = [22, 50, 75, 150];
            idx = randi(numel(pwrChoices));
            pwrRoad = pwrChoices(idx);   % Randomly select 22, 50, 75, or 150 kW
        
            % Format the road charger string for output (AC for 22 kW, DC otherwise)
            if pwrRoad == 22
                pwrStr = sprintf('AC_%dkW', pwrRoad);
            else
                pwrStr = sprintf('DC_%dkW', pwrRoad);
            end
        
            chgRoad = "Yes_" + pwrStr;   % Record the charger type used for on-road charging
        
            % Calculate the "over distance" (portion of driving beyond rated range)
            overDist   = abs(totalDist - range);
            overCap    = (use * overDist)/1000;    % Extra energy needed, in kWh
        
            % Charging time on road (for "over" energy only, includes charging losses)
            timeRoad   = overCap * (1 + charloss/100) / pwrRoad;
        
            % Total charging time: on-road charging + depot charging to reach SoC
            % The time to fill up to target SoC (may require additional charging after on-road session)
            % This formula accounts for (a) charging the "over" portion on road, (b) remaining needed to reach SoC at depot
            timeToFull=timeRoad+(usedCap-overCap - capFull*(1 - SOC/100)) * (1 + charloss/100) / pwr;
        end
        
        % --- Convert charging times to [hours, minutes] format for output/display
        hRoad = floor(timeRoad); 
        mRoad = round(mod(timeRoad,1)*60);
        hchg  = floor(timeToFull); 
        mchg  = round(mod(timeToFull,1)*60);

        % --- Fill output struct for this day (formatted fields)
        P.(day) = struct( ...
        'Purpose', purpose, ...
        'Day', day, ...
        'Temperature', sprintf('%d °C',round(tempRandom)), ...
        'Consumption', sprintf('%d Wh/km',round(use)), ...
        'FullCapacity', sprintf('%d kWh',round(capFull)), ...
        'CapacityWithTemperatur', sprintf('%d kWh',round(cap)), ...
        'PercentOperatingCapacity', sprintf('%.1f %%',capTemp), ...
        'FullRange', sprintf('%d km',round(rangeFull)), ...
        'RangeWithTemperatur', sprintf('%d km',round(range)), ...
        'PercentOperatingRange', sprintf('%.1f %%',rangeTemp), ...
        'Distance', sprintf('%d km',round(totalDist)), ...
        'AvgSpeed', sprintf('%d km/h',round(avgspeed)), ...
        'ChargingLocation', loc, ...
        'SoC', sprintf('%.1f %%',SOC), ...
        'ChargingType', ctype, ...
        'PercentChargingLoss', sprintf('%.1f %%',charloss), ...
        'TripNumber', sprintf('%d trips',Ntrip), ...
        'TripStart', startStr, ...
        'TripEnd', endStr, ...
        'RunTime', sprintf('%dh %dmin',floor(runT),round(mod(runT,1)*60)), ...
        'StopTime', stopStr, ...
        'ChargeOnRoad', chgRoad, ...
        'BatteryPerc', sprintf('%.1f %%',remPerc), ...
        'ChargingTimeOnRoad', sprintf('%dh %dmin',hRoad,mRoad), ...
        'TotalTimeToCharge', sprintf('%dh %dmin',hchg,mchg) ...
        );

      % store into profiles
      P.(day) = F;
      P.(day).Purpose                        = purpose;
      P.(day).Day                            = days{d};
      P.(day).Temperature                    = sprintf('%d °C', round(tempRandom));
      P.(day).Consumption                    = sprintf('%d Wh/km', round(use));
      P.(day).FullCapacity                   = sprintf('%d kWh', round(capFull));
      P.(day).CapacityWithTemperatur         = sprintf('%d kWh', round(cap));
      P.(day).PercentOperatingCapacity       = sprintf('%.1f %%', round(capTemp,1));
      P.(day).FullRange                      = sprintf('%d km', round(rangeFull));
      P.(day).RangeWithTemperatur            = sprintf('%d km', round(range));
      P.(day).PercentOperatingRange          = sprintf('%.1f %%',round(rangeTemp,1)); 
      P.(day).Distance                       = sprintf('%d km', round(totalDist));
      P.(day).AvgSpeed                       = sprintf('%d km/h',round(avgspeed));
      P.(day).ChargingLocation               = loc;
      P.(day).SoC                            = sprintf('%.1f %%',round(SOC));
      P.(day).ChargingType                   = ctype;
      P.(day).PercentChargingLoss            = sprintf('%.1f %%',round(charloss,1));
      P.(day).TripNumber                     = sprintf('%d trips',Ntrip);
      P.(day).TripStart                      = startStr;
      P.(day).TripEnd                        = endStr;
      P.(day).TimeToCharge                   = sprintf('%dh %dmin', hchg, mchg);
      P.(day).RunTime                        = sprintf('%dh %dmin', floor(runT), round(mod(runT,1)*60));
      P.(day).StopTime                       = stopStr;      
      P.(day).ChargeOnRoad                   = chgRoad;
      P.(day).BatteryPerc                    = sprintf('%.1f %%', remPerc);
      P.(day).ChargingTimeOnRoad             = sprintf('%dh %dmin', hRoad, mRoad);
      P.(day).TotalTimeToCharge              = sprintf('%dh %dmin', hchg, mchg);
    end

    % --- Display workday/weekend results to file and/or screen
    myprint(fid, '--- Simulation %d: Workday ---\n', i);
    mydisp(fid, P.Workday);

    myprint(fid, '--- Simulation %d: Weekend ---\n', i);
    mydisp(fid, P.Weekend);

    myprint(fid, '\n');
  end
end