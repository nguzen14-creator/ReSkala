function profiles = generatePKWProfiles(purposes,randomSizes, segmentFile, chargingTypesFile,fid)
%GENERATEPKWPROFILES  Generate PKW (car) mobility profiles for given purposes and sizes
%   profiles = generatePKWProfiles(purposes,randomSizes, segmentFile, chargingTypesFile, fid)
%   - Generates mobility and charging profiles for a number of PKWs (cars).
%   - Supports three purposes: 'Job & Education', 'Private', and 'Service'.
%   - For each car: 
%       * selects technical data and compatible charging types
%       * simulates daily schedules for workdays/weekends according to rules
%       * applies temperature effects and random variation
%       * computes energy, battery, and charging parameters
%   - Outputs one struct per PKW per day type, formatted for easy display or table use.
%
%   Input:
%     purposes         : cell array of strings, each PKW's primary purpose
%     randomSizes      : cell array of PKW segment/size strings (e.g., 'small', 'medium', etc.)
%     segmentFile      : CSV file with EV segment technical data
%     chargingTypesFile: CSV with charging compatibility information
%     fid              : file id for printing output
%
%   Output:
%     profiles: struct array with all fields for each PKW/day

    % --- Load technical and compatibility data from input files ---
    Tseg   = readEVsegment(segmentFile);                 % All EV segment specs
    Ctypes = readChargingCompatible(chargingTypesFile);  % Which charger types fit each segment

    % --- Read temperature-dependent performance table ---
    opts = detectImportOptions('Temperatur.CSV', 'Delimiter', ',');
    opts.VariableNamingRule = 'preserve';
    T = readtable('Temperatur.CSV',opts);

    % --- Get full temperature range covered in data table ---
    overallMin = min(T.Temp_from);
    overallMax = max(T.Temp_to);

    % --- Find all compatible charger types for PKW segment ---
    locations = ["Public", "Private"];   % Used for AC charger assignment
    pkwRow = Ctypes(strcmp(Ctypes.Segment,'PKW'), :);  % Row for PKW
    vars = Ctypes.Properties.VariableNames(2:end);     % Charger types are columns 2:end
    compatible = vars( pkwRow{1,2:end} );              % Logical vector: which chargers are compatible

    N = length(purposes);   % Number of PKWs to process

    % --- Loop over each PKW (by purpose/size) ---
    for i = 1:N
        % --- Technical profile: select segment/size row
        randomSize = randomSizes(i);           % Size (e.g., 'Small', 'Compact', etc.)
        purpose = purposes(i);                 % Purpose string for this PKW

        idx = strcmp(Tseg.Segment, randomSize);% Row index for this PKW segment/size

        % --- Extract capacity/range for this PKW type ---
        capMin = Tseg.NomCap_min(idx);
        capMax = Tseg.NomCap_max(idx);
        rangeMin = Tseg.Range_min(idx);
        rangeMax = Tseg.Range_max(idx);

        % --- Draw a random ambient temperature for this simulation ---
        tempRandom = overallMin + (overallMax - overallMin)*rand();
        % Find the first temperature row whose interval contains tempRandom
        idxLogical = (T.Temp_from <= tempRandom) & (tempRandom <= T.Temp_to);
        idxRow = find(idxLogical, 1, 'first');
        if isempty(idxRow)
            error("No range found for temperature %.2f!", tempRandom);
        end

        % --- Apply temperature to min/max capacity and range values (simulates loss) ---
        capMinTemp   = T.("Capacity_min")(idxRow);
        capMaxTemp   = T.("Capacity_max")(idxRow);
        rangeMinTemp = T.("Range_min")(idxRow);
        rangeMaxTemp = T.("Range_max")(idxRow);

        % --- Draw a random value for the actual operational loss at this temp ---
        capTemp = capMinTemp + (capMaxTemp - capMinTemp)*rand();      % % usable capacity
        rangeTemp    = rangeMinTemp + (rangeMaxTemp - rangeMinTemp)*rand(); % % usable range
        capLoss   = 100 - capTemp;    % % capacity loss

        % --- Pick a random full battery and full range (varies across the population) ---
        capFull   = capMin   + (capMax   - capMin)   * rand;
        rangeFull = rangeMin + (rangeMax - rangeMin) * rand;

        % --- Actual capacity/range after temperature effects ---
        cap   = capFull   * capTemp   / 100;    
        range = rangeFull * rangeTemp / 100;

        % --- Compute energy usage in Wh/km ---
        use = capFull * 1000 / rangeFull;     % (kWh→Wh/km, for base full-range driving)

        % --- Randomly select a compatible charger for this PKW ---
        ctype = compatible{ randi(numel(compatible)) };      % e.g., 'AC_11kW'
        % Extract power value (kW) from charger type string (may be 'AC_7.4kW', 'DC_150kW', etc.)
        pwr = str2double( regexp(ctype,'\d+(\.\d+)?','match','once') );
        % If 7.4 kW AC, randomly upgrade to 11kW in half of cases (simulates real-world variation)
        if abs(pwr - 7.4) < 1e-6
            if rand() < 0.5
                pwr = 7.4;
            else
                pwr = 11;
            end
        end

        % --- Assign charging location and state-of-charge (SOC) target based on charger type ---
        if startsWith(ctype,'DC')
            loc = 'Public'; SOC = 80;              % Fast DC is always public, charge to 80% (common practice)
        elseif startsWith(ctype,'AC')
            loc = locations(randi(2)); SOC = 100;  % AC can be public or private, charge to 100%
        else
            loc = 'Private'; SOC = 100;            % Unknown charger types → private, full charge
        end

        % --- Output struct template for this PKW, will be filled for Workday/Weekend ---
        F = struct( ...
            'Purpose', [],'Day',[],'Temperature', [],'Consumption', [],'FullCapacity', [], ...
            'CapacityWithTemperatur',[] ,'PercentOperatingCapacity', [],'FullRange', [], ...
            'RangeWithTemperatur',[],'PercentOperatingRange', [],'Distance', [],'AvgSpeed', [], ...
            'ChargingLocation', [],'ChargingType', [], 'SoC' , [],'PercentChargingLoss',[], ...
            'TripNumber', [], 'TripStart', [], 'TripEnd', [],'RunTime', [],'StopTime', [], ...
            'ChargeOnRoad',[],'ChargingTimeOnRoad',[],'BatteryPerc', [], 'TotalTimeToCharge', [] );
        profiles = repmat(F, N, 2);

        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        %--- PURPOSE: 'Job & Education' ---------%
        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

        if strcmpi(purpose, 'Job & Education') 
            % --- Pick a distance bin for this PKW on this day
            %  60% short (<100km), 30% medium (100-300km), 10% long (≥300km)
            r = rand();
            if     r < 0.60
                distBin = 1;    
            elseif r < 0.90
                distBin = 2;    
            else
                distBin = 3;    
            end

            % --- Define rules for trip times based on weekday/weekend
            days = {'Workday','Weekend'};
            for d = 1:2
                day = days{d};
                if d==1
                    % --- Workday trip rules (early start, short first trip, long stop)
                    startWin      = [5,   9];     % 5:00–9:00 trip 1 start
                    dur1Range     = [0.1, 1];     % 6–60min trip 1 duration
                    stop1Range    = [4,   9];     % 4–9h stop after trip 1
                    durOtherRange = [0.1, 1];     % next trip durations 6–60min
                    stopOtherRange= [0.1, 2];     % next stops 6–120min
                else
                    % --- Weekend: broader trip start, more variety in durations/stops
                    startWin      = [5,  18];     
                    dur1Range     = [0.1, 1.5];   
                    stop1Range    = [0.1,10];     
                    durOtherRange = [0.1, 1.5];   
                    stopOtherRange= [0.1,10];     
                end

                % --- Number of trips: pick 2–4 per day
                Ntrip = randi([2,4]);

                % --- Generate trips until all schedule/usage rules are met
                valid = false;
                while ~valid
                    % --- Generate first trip timing
                    start1 = startWin(1) + diff(startWin)*rand();
                    dur1   = dur1Range(1) + diff(dur1Range)*rand();
                    stop1  = stop1Range(1) + diff(stop1Range)*rand();
                    starts = zeros(1,Ntrip);
                    ends   = zeros(1,Ntrip);
                    durs   = zeros(1,Ntrip);
                    stops  = zeros(1,Ntrip);
                    starts(1) = start1;
                    ends(1)   = start1 + dur1;
                    durs(1)   = dur1;
                    stops(1)  = stop1;
                    % --- Loop over subsequent trips
                    for t = 2:Ntrip
                        starts(t) = ends(t-1) + stops(t-1);
                        dur_t     = durOtherRange(1) + diff(durOtherRange)*rand();
                        stop_t    = stopOtherRange(1) + diff(stopOtherRange)*rand();
                        ends(t)   = starts(t) + dur_t;
                        durs(t)   = dur_t;
                        stops(t)  = stop_t;
                    end

                    % --- Key constraints for validity:
                    %   • All trips done before midnight
                    %   • 1st trip not excessively long compared to rest
                    if ends(end)>24 || dur1>sum(durs(2:end))+(10/60)
                        continue
                    end

                    % --- Calculate running/driving time, assign speeds and split by road type
                    runT = sum(durs);
                    t_urban  = runT * 0.26;
                    t_rural  = runT * 0.41;
                    t_highway= runT * 0.33;
                    v_urban  = 24  + (rand*10 - 5);
                    v_rural  = 80  + (rand*10 - 5);
                    v_highway= 118 + (rand*10 - 5);
                    dist_urban  = v_urban  * t_urban;
                    dist_rural  = v_rural  * t_rural;
                    dist_highway= v_highway * t_highway;
                    totalDist   = dist_urban + dist_rural + dist_highway;

                    % --- Enforce daily distance bin (short, medium, long)
                    switch distBin
                        case 1
                            if totalDist >= 100,    continue;  end
                        case 2
                            if totalDist < 100 || totalDist >= 300, continue; end
                        case 3
                            if totalDist < 300,    continue;  end
                    end

                    valid = true; % This trip schedule is valid!
                end  % while ~valid

                % --- Format trip times for output
                startStr = arrayfun(@(x) sprintf('%dh %02dmin', floor(x), round(mod(x,1)*60)), starts,  'Uni',false);
                endStr   = arrayfun(@(x) sprintf('%dh %02dmin', floor(x), round(mod(x,1)*60)), ends,    'Uni',false);
                stopStr  = arrayfun(@(x) sprintf('%dh %02dmin', floor(x), round(mod(x,1)*60)), stops,  'Uni',false);

                avgspeed = totalDist / runT;

                % --- Compute battery remaining after all trips
                usedWh   = use * totalDist;
                remPerc  = max(0, (cap*1000 - usedWh)/(cap*1000)*100);

                % --- Assign charging losses, which depend on charger type
                charlossDC = 6 + (8 - 6)*rand;
                charlossAC = 5 + (10 - 5)*rand;
                if remPerc < 80
                    if startsWith(ctype,'DC')
                        charloss = charlossDC;
                    else
                        charloss = charlossAC;
                    end
                else
                    SOC=''; % No charging needed, so SoC field is blank
                    charloss = 0;
                end

                % --- Charging time calculations: whether charging is needed and where
                usedCap = (use .* totalDist) /1000 ;       % used capacity in kWh
                if totalDist < (range - 20)
                    remPerc = round((capFull - usedCap - capFull*capLoss/100)*100/ capFull); 
                    chgRoad = 'No';              % no charging on the road
                    timeRoad = 0.0;                % charging time on the road
                    if remPerc < 80
                        currentWh = capFull * (remPerc / 100);
                        targetWh = capFull * SOC/100;
                        energyToCharge = targetWh - currentWh; 
                        timeToFull = energyToCharge * (1 + charloss/100) / pwr;                  
                    else
                        timeToFull = 0.0;
                    end
                else
                    remPerc    = '';
                    % --- On-road charging required, pick a random power
                    pwrChoices = [22, 50, 75, 150];
                    idx = randi(numel(pwrChoices));
                    pwrRoad = pwrChoices(idx);
                    if pwrRoad == 22
                        pwrStr = sprintf('AC_%dkW', pwrRoad);
                    else
                        pwrStr = sprintf('DC_%dkW', pwrRoad);
                    end

                    chgRoad = "Yes_" + pwrStr;  % charging on the road
                    overDist   = abs(totalDist - range);
                    overCap    = (use * overDist)/1000; % Used capacity exceeds capacity limit in kWh
                    timeRoad   = overCap * (1 + charloss/100) / pwrRoad; % charging time on the road 
                    timeToFull=timeRoad+(usedCap-overCap - capFull*(1 - SOC/100)) * (1 + charloss/100) / pwr;
                end

                % --- Format charging times for output
                hRoad = floor(timeRoad);
                mRoad = round(mod(timeRoad, 1) * 60);
                hchg = floor(timeToFull);
                mchg = round(mod(timeToFull, 1) * 60);

                % --- Fill your output struct for this day
                P.(day) = F;
                P.(day).Purpose             = purpose;
                P.(day).Day                 = days{d};
                P.(day).Temperature         = sprintf('%d °C', round(tempRandom));
                P.(day).Consumption         = sprintf('%d Wh/km', round(use));
                P.(day).FullCapacity         = sprintf('%d kWh', round(capFull));
                P.(day).CapacityWithTemperatur = sprintf('%d kWh', round(cap));
                P.(day).PercentOperatingCapacity    = sprintf('%.1f %%', round(capTemp,1));
                P.(day).FullRange         = sprintf('%d km', round(rangeFull));
                P.(day).RangeWithTemperatur    = sprintf('%d km', round(range));
                P.(day).PercentOperatingRange        = sprintf('%.1f %%',round(rangeTemp,1)); 
                P.(day).Distance = sprintf('%d km', round(totalDist));
                P.(day).AvgSpeed          = sprintf('%d km/h',round(avgspeed));
                P.(day).ChargingLocation           = loc;
                P.(day).SoC            = sprintf('%.1f %%',round(SOC));
                P.(day).ChargingType             = ctype;
                P.(day).PercentChargingLoss            = sprintf('%.1f %%',round(charloss,1));
                P.(day).TripNumber            = sprintf('%d trips',Ntrip);
                P.(day).TripStart            = startStr;
                P.(day).TripEnd         = endStr;
                P.(day).TimeToCharge        = sprintf('%dh %dmin', hchg, mchg);
                P.(day).RunTime               = sprintf('%dh %dmin', floor(runT), round(mod(runT,1)*60));
                P.(day).StopTime              = stopStr;      
                P.(day).ChargeOnRoad          = chgRoad;
                P.(day).BatteryPerc           = sprintf('%.1f %%', remPerc);
                P.(day).ChargingTimeOnRoad    = sprintf('%dh %dmin', hRoad, mRoad);
                P.(day).TotalTimeToCharge     = sprintf('%dh %dmin', hchg, mchg);
            end

            % --- Print simulation result for this PKW
            myprint(fid, '--- Simulation %d: Workday ---\n', i);
            mydisp(fid, P.Workday);
            myprint(fid, '--- Simulation %d: Weekend ---\n', i);
            mydisp(fid, P.Weekend);
            myprint(fid, '\n');

        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        %--- PURPOSE: 'Private' -----------------------------%
        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

        elseif strcmpi(purpose, 'Private')    % Check if current PKW is for "Private" purpose

        %--- Pick a daily distance category ("distance-bin") for this vehicle
        % 60% probability: <100km, 30%: 100–299km, 10%: ≥300km
        r = rand();                   % Generate a random number between 0 and 1
        if     r < 0.60
          distBin = 1;                % 1 = "short": total distance < 100 km
        elseif r < 0.60+0.30
          distBin = 2;                % 2 = "medium": total distance 100–299 km
        else
          distBin = 3;                % 3 = "long": total distance ≥ 300 km
        end
    
        %--- Simulate profiles for both workday and weekend for each vehicle
        days = {'Workday','Weekend'};
        for d = 1:2
          day = days{d};              % Set current day label
    
          %--- Set trip generation rules for each day type
          if d==1
            % For Workdays:
            startWin       = [5,  18];    % Allow trip 1 to start between 05:00–18:00
            dur1Range      = [0.1, 2];    % Trip 1 duration between 0.1–2 hours
            stop1Range     = [0.1,10];    % Stop after trip 1: 0.1–10 hours
            durOtherRange  = [0.1, 2];    % All other trips: duration 0.1–2 hours
            stopOtherRange = [0.1,10];    % All other stops: duration 0.1–10 hours
          else
            % For Weekends: allow later/longer trips, wider windows
            startWin       = [5,  20];    % Trip 1 can start between 05:00–20:00
            dur1Range      = [0.1, 3];    % Trip 1 duration between 0.1–3 hours
            stop1Range     = [0.1,10];    % Stop after trip 1: 0.1–10 hours
            durOtherRange  = [0.1, 2];    % All other trips: duration 0.1–2 hours
            stopOtherRange = [0.1,10];    % All other stops: duration 0.1–10 hours
          end
    
          %--- Randomly select number of trips for the day (between 2 and 4)
          Ntrip = randi([2,4]);
    
          %--- Loop until a valid set of trip and stop times is found
          valid = false;
          while ~valid
            %--- Generate timing for Trip 1
            start1      = startWin(1) + diff(startWin)*rand();     % Trip 1 start time within allowed window
            dur1        = dur1Range(1) + diff(dur1Range)*rand();   % Trip 1 duration
            stop1       = stop1Range(1) + diff(stop1Range)*rand(); % Stop after trip 1
    
            %--- Initialize arrays for trip start/end/duration/stop times
            starts      = zeros(1,Ntrip);
            ends        = zeros(1,Ntrip);
            durs        = zeros(1,Ntrip);
            stops       = zeros(1,Ntrip);
            starts(1)   = start1;
            ends(1)     = start1 + dur1;
            durs(1)     = dur1;
            stops(1)    = stop1;
    
            %--- Generate timing for Trips 2…Ntrip
            for t = 2:Ntrip
              starts(t) = ends(t-1) + stops(t-1);                           % Start = previous end + previous stop
              durs(t)   = durOtherRange(1) + diff(durOtherRange)*rand();    % Random duration for this trip
              stops(t)  = stopOtherRange(1) + diff(stopOtherRange)*rand();  % Random stop after this trip
              ends(t)   = starts(t) + durs(t);                              % End = start + duration
            end
    
            %--- Enforce logical constraints on the day’s trips
            % 1. Last trip must end before midnight (≤24h)
            % 2. The first trip cannot be excessively long compared to sum of others (max 10 min longer)
            if ends(end)>24 || dur1>sum(durs(2:end))+(10/60)
              continue    % If constraints not met, repeat the loop with new timings
            end
    
            %--- All timing constraints passed if we get here
    
            %--- Calculate total running/driving time (sum of trip durations)
            runT = sum(durs);
    
            %--- Simulate proportion of time on different road types (urban/rural/highway)
            % Fractions reflect typical PKW distribution in Germany
            t_urban   = runT * 0.26;  % 26% urban
            t_rural   = runT * 0.41;  % 41% rural
            t_highway = runT * 0.33;  % 33% highway
    
            %--- Simulate typical average speeds for each road type, ±5 km/h
            v_urban   = 24  + (rand*10 - 5);     % 24±5 km/h
            v_rural   = 80  + (rand*10 - 5);     % 80±5 km/h
            v_highway = 118 + (rand*10 - 5);     % 118±5 km/h
    
            %--- Compute distance traveled in each segment
            dist_urban   = v_urban   * t_urban;
            dist_rural   = v_rural   * t_rural;
            dist_highway = v_highway * t_highway;
            totalDist    = dist_urban + dist_rural + dist_highway;  % Total km driven that day
    
            %--- Enforce daily distance constraint based on previously selected bin
            % (matches with statistics for private cars)
            switch distBin
              case 1
                if totalDist >= 100,    continue;  end           % If short bin, must be <100km
              case 2
                if totalDist < 100 || totalDist >= 300, continue; end % Medium bin: [100,300)
              case 3
                if totalDist < 300,    continue;  end            % Long bin: ≥300km
            end
    
            %--- If all constraints are satisfied, exit the loop
            valid = true;
          end  % while ~valid
    
          %--- Format trip times for output as strings (e.g. "10h 35min")
          startStr = arrayfun(@(x) sprintf('%dh %02dmin', floor(x), round(mod(x,1)*60)), starts,  'Uni',false);
          endStr   = arrayfun(@(x) sprintf('%dh %02dmin', floor(x), round(mod(x,1)*60)), ends,    'Uni',false);
          stopStr  = arrayfun(@(x) sprintf('%dh %02dmin', floor(x), round(mod(x,1)*60)), stops,  'Uni',false);
    
          %--- Calculate average speed for the day's trips
          avgspeed = totalDist / runT;
    
          %--- Calculate battery state-of-charge after all trips (as %)
          usedWh   = use * totalDist;                    % Total Wh used = consumption * distance
          remPerc  = max(0, (cap*1000 - usedWh)/(cap*1000)*100);  % Remaining % SoC (not below 0)
    
          %--- Assign random charging loss factors depending on charger type (AC/DC)
          charlossDC = 6 + (8 - 6)*rand;     % DC charging: 6–8% loss
          charlossAC = 5 + (10 - 5)*rand;    % AC charging: 5–10% loss
          if remPerc < 80
              if startsWith(ctype,'DC')
                  SOC=80;                    % For DC, charge to 80%
                  charloss = charlossDC;
              else
                  SOC=100;                   % For AC, charge to 100%
                  charloss = charlossAC;
              end
          else
              SOC='';                        % If above 80%, no charging needed
              charloss = 0;
          end
    
          %--- Charging needs and calculations
          usedCap = (use .* totalDist) /1000 ;   % Total kWh used in the day
          if totalDist < (range - 20)
              % All trips can be completed within battery range (with 20km buffer)
              remPerc = round((capFull - usedCap - capFull*capLoss/100)*100/ capFull); 
              chgRoad = 'No';              % No charging on the road needed
              timeRoad = 0.0;              % No time spent charging en route
              if remPerc < 80
                  currentWh = capFull * (remPerc / 100);          % Remaining battery energy in kWh
                  targetWh = capFull * SOC/100;                   % Desired SoC target in kWh
                  energyToCharge = targetWh - currentWh;          % kWh to recharge
                  timeToFull = energyToCharge * (1 + charloss/100) / pwr;  % Charging time (hours)
              else
                  timeToFull = 0.0;                               % No charging required
              end
          else
              % Trips exceed single-charge range (with buffer); on-road charging is needed
              remPerc    = '';
              pwrChoices = [22, 50, 75, 150];         % Possible charging power ratings (kW)
              idx = randi(numel(pwrChoices));
              pwrRoad = pwrChoices(idx);              % Randomly select road charging power
              if pwrRoad == 22
                  pwrStr = sprintf('AC_%dkW', pwrRoad);
              else
                  pwrStr = sprintf('DC_%dkW', pwrRoad);
              end
    
              chgRoad = "Yes_" + pwrStr;              % On-road charging event and power type
    
              % Calculate additional energy needed for "over distance"
              overDist   = abs(totalDist - range);    % Distance beyond battery range (km)
              overCap    = (use * overDist)/1000;     % Extra kWh required for over distance
              timeRoad   = overCap * (1 + charloss/100) / pwrRoad; % Charging time on road (h)
              % Total time includes on-road + depot charging to SoC
              timeToFull=timeRoad+(usedCap-overCap - capFull*(1 - SOC/100)) * (1 + charloss/100) / pwr;
          end
    
          %--- Convert charging times to "Xh Ymin" format for display
          hRoad = floor(timeRoad);
          mRoad = round(mod(timeRoad, 1) * 60);
    
          hchg = floor(timeToFull);
          mchg = round(mod(timeToFull, 1) * 60);
    
          %--- Fill structured output for this day's profile (for table/file/display)
          P.(day) = struct( ...
            'Purpose',          purpose, ...
            'Day',              days{d}, ...
            'Temperature',         tempRandom, ...
            'Consumption',     use, ...
            'FullCapacity',      capFull, ...
            'CapacityWithTemperatur', cap, ...
            'PercentOperatingCapacity',    capTemp, ...
            'FullRange',         rangeFull, ...
            'RangeWithTemperatur',    range, ...
            'PercentOperatingRange',        rangeTemp, ...
            'Distance', totalDist, ...
            'AvgSpeed',          avgspeed, ...
            'ChargingLocation',           loc, ...
            'SoC',             SOC, ...
            'ChargingType', ctype, ...
            'PercentChargingLoss', charloss, ...
            'TripNumber', Ntrip, ...
            'TripStart', startStr, ...
            'TripEnd', endStr, ...
            'RunTime',             sprintf('%dh %dmin', floor(runT), round(mod(runT,1)*60)), ...
            'StopTime',            stopStr, ...
            'ChargeOnRoad',            chgRoad, ...
            'BatteryPerc',            remPerc, ...
            'ChargingTimeOnRoad',         sprintf('%dh %dmin', hRoad, mRoad), ...
            'TotalTimeToCharge',        sprintf('%dh %dmin', hchg, mchg) ...
          );
    
          % Here, fields are formatted nicely for table/export.
            P.(day) = F;
            P.(day).Purpose             = purpose;
            P.(day).Day                 = days{d};
            P.(day).Temperature         = sprintf('%d °C', round(tempRandom));
            P.(day).Consumption         = sprintf('%d Wh/km', round(use));
            P.(day).FullCapacity         = sprintf('%d kWh', round(capFull));
            P.(day).CapacityWithTemperatur = sprintf('%d kWh', round(cap));
            P.(day).PercentOperatingCapacity    = sprintf('%.1f %%', round(capTemp,1));
            P.(day).FullRange         = sprintf('%d km', round(rangeFull));
            P.(day).RangeWithTemperatur    = sprintf('%d km', round(range));
            P.(day).PercentOperatingRange        = sprintf('%.1f %%',round(rangeTemp,1)); 
            P.(day).Distance = sprintf('%d km', round(totalDist));
            P.(day).AvgSpeed          = sprintf('%d km/h',round(avgspeed));
            P.(day).ChargingLocation           = loc;
            P.(day).SoC            = sprintf('%.1f %%',round(SOC));
            P.(day).ChargingType             = ctype;
            P.(day).PercentChargingLoss            = sprintf('%.1f %%',round(charloss,1));
            P.(day).TripNumber            = sprintf('%d trips',Ntrip);
            P.(day).TripStart            = startStr;
            P.(day).TripEnd         = endStr;
            P.(day).RunTime               = sprintf('%dh %dmin', floor(runT), round(mod(runT,1)*60));
            P.(day).StopTime              = stopStr;      
            P.(day).ChargeOnRoad          = chgRoad;
            P.(day).BatteryPerc           = sprintf('%.1f %%', remPerc);
            P.(day).ChargingTimeOnRoad    = sprintf('%dh %dmin', hRoad, mRoad);
            P.(day).TotalTimeToCharge     = sprintf('%dh %dmin', hchg, mchg);
    
          %--- For display: print simulation results for both day types
          myprint(fid, '--- Simulation %d: Workday ---\n', i);
          mydisp(fid, P.Workday);
    
          myprint(fid, '--- Simulation %d: Weekend ---\n', i);
          mydisp(fid, P.Weekend);
    
          myprint(fid, '\n');
        end % End day loop

        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        %--- PURPOSE: 'Service' -----------------------------%
        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

        elseif strcmpi(purpose, 'Service')
        %--- For "Service" vehicles: set the daily total distance probability bin
        % 20%: <100km, 60%: 100-300km, 20%: >=300km (matching typical service vehicle usage)
        r = rand();
        if     r < 0.20
          distBin = 1;    % Short day (<100km)
        elseif r < 0.20+0.60
          distBin = 2;    % Medium day (100-299km)
        else
          distBin = 3;    % Long day (>=300km)
        end
        
        %--- Simulate profiles for both workdays and weekends
        days = {'Workday','Weekend'};    
        for d = 1:2
          day = days{d};
        
          %--- Set the rules for trip/stop generation depending on day type
          if d==1
            % Workday: early and longer service hours, larger window for first trip
            startWin       = [4,  15];      % First trip can start 04:00–15:00
            dur1Range      = [0.1, 2.5];    % First trip duration 0.1–2.5h
            stop1Range     = [0.1, 1.5];    % First stop 0.1–1.5h
            durOtherRange  = [0.1, 2.5];    % Other trip durations 0.1–2.5h
            stopOtherRange = [0.1, 1.5];    % Other stops 0.1–1.5h
          else
            % Weekend: later, usually shorter operating hours
            startWin       = [6,  12];      % First trip can start 06:00–12:00
            dur1Range      = [0.1, 2];      % First trip duration 0.1–2h
            stop1Range     = [0.1, 1.5];    % First stop 0.1–1.5h
            durOtherRange  = [0.1, 2];      % Other trip durations 0.1–2h
            stopOtherRange = [0.1, 1.5];    % Other stops 0.1–1.5h
          end
        
          %--- Pick random number of trips for the day (between 2 and 4)
          Ntrip = randi([2,4]);
        
          %--- Build the sequence until all logical constraints are fulfilled
          % Constraints for realistic "service" patterns:
          %   1. Last trip must end within 24h
          %   2. (Commented out) Trip1 can't be much longer than all others combined (+10min)
          %   3. Total stop time must be between 1h and 3h (service work between stops)
          %   4. The "shift window" (End of last trip - start of first) must be 4–10h
          valid = false;
          while ~valid
            %--- Trip 1 timings
            start1     = startWin(1) + diff(startWin)*rand();  % Random start in window
            dur1       = dur1Range(1) + diff(dur1Range)*rand();% Random trip 1 duration
            stop1      = stop1Range(1) + diff(stop1Range)*rand(); % Random stop after trip 1
        
            %--- Arrays to collect times for all trips and stops
            starts     = zeros(1,Ntrip);
            ends       = zeros(1,Ntrip);
            durs       = zeros(1,Ntrip);
            stops      = zeros(1,Ntrip);
            starts(1)  = start1;
            ends(1)    = start1 + dur1;
            durs(1)    = dur1;
            stops(1)   = stop1;
        
            %--- Build timings for all remaining trips (2...Ntrip)
            for t = 2:Ntrip
              starts(t) = ends(t-1) + stops(t-1);   % Each trip starts after previous trip + stop
              durs(t)   = durOtherRange(1) + diff(durOtherRange)*rand(); % Duration for this trip
              stops(t)  = stopOtherRange(1) + diff(stopOtherRange)*rand(); % Stop after this trip
              ends(t)   = starts(t) + durs(t);      % This trip ends after its duration
            end
        
            %--- Check 1: Does last trip end before midnight?
            if ends(end) > 24
              continue    % If not, resample all timings
            end
        
        
            %--- Check 2: Total stop time within [1,3] hours?
            totalStop = sum(stops);
            if totalStop < 1 || totalStop > 3
              continue    % If not, repeat
            end
        
            %--- Check 3: Total "window" (EndN - Start1) within [4,10] hours?
            window = ends(end) - starts(1);
            if window < 4 || window > 10
              continue
            end
        
            %--- All constraints satisfied: proceed
        
            %--- Calculate total running/driving time (sum of trip durations)
            runT = sum(durs);
        
            %--- Split the driving time into segments by road type
            % For PKW: 26% urban, 41% rural, 33% highway (adjust as needed for service vans)
            t_urban    = runT * 0.26;
            t_rural    = runT * 0.41;
            t_highway  = runT * 0.33;
        
            %--- Randomize average speeds for each segment, ±5km/h to introduce day-to-day variation
            v_urban    = 24  + (rand*10 - 5);
            v_rural    = 80  + (rand*10 - 5);
            v_highway  = 118 + (rand*10 - 5);
        
            %--- Compute distances for each segment
            dist_urban    = v_urban   * t_urban;
            dist_rural    = v_rural   * t_rural;
            dist_highway  = v_highway * t_highway;
            totalDist     = dist_urban + dist_rural + dist_highway;
        
            %--- Enforce the "distance bin" selection from the start
            switch distBin
              case 1
                if totalDist >= 100,    continue;  end   % For short day, must be under 100km
              case 2
                if totalDist < 100 || totalDist >= 300, continue; end % Medium: 100–299km
              case 3
                if totalDist < 300,    continue;  end    % Long: must be at least 300km
            end
        
            %--- If all constraints met, exit the loop
            valid = true;
          end  % while ~valid
        
          %--- Format all trip start/end/stop times as "hh h mm min" strings for output
          startStr = arrayfun(@(x) sprintf('%dh %02dmin', floor(x), round(mod(x,1)*60)), starts,  'Uni',false);
          endStr   = arrayfun(@(x) sprintf('%dh %02dmin', floor(x), round(mod(x,1)*60)), ends,    'Uni',false);
          stopStr  = arrayfun(@(x) sprintf('%dh %02dmin', floor(x), round(mod(x,1)*60)), stops,  'Uni',false);
        
          %--- Compute average speed over all trips
          avgspeed = totalDist / runT;
        
          %--- Compute battery consumption and remaining SoC (%)
          usedWh   = use * totalDist;                     % Total Wh used
          remPerc  = max(0, (cap*1000 - usedWh)/(cap*1000)*100); % Remaining battery percent, never below 0
        
          %--- Charging losses: randomly select for AC (5–10%) or DC (6–8%)
          charlossDC = 6 + (8 - 6)*rand;
          charlossAC = 5 + (10 - 5)*rand;
          if remPerc < 80
              if startsWith(ctype,'DC')
                  % If DC charger: only charge to 80% to protect battery
                  charloss = charlossDC;
              else
                  % If AC charger: can charge to 100%
                  charloss = charlossAC;
              end
          else
              % If enough battery left, skip charging
              SOC='';        % No charging needed
              charloss = 0;
          end
        
          %--- Determine if on-road charging is needed
          usedCap = (use .* totalDist) /1000;    % kWh used
          if totalDist < (range - 20)
            % Enough range: no on-road charging
            remPerc = round((capFull - usedCap - capFull*capLoss/100)*100/ capFull); 
            chgRoad = 'No';
            timeRoad = 0.0;
            if remPerc < 80
                % Charging at depot/home to fill up
                currentWh = capFull * (remPerc / 100);
                targetWh = capFull * SOC/100;
                energyToCharge = targetWh - currentWh; 
                timeToFull = energyToCharge * (1 + charloss/100) / pwr;                  
            else
                timeToFull = 0.0;
            end
          else
            % Range exceeded: need on-road charging
            remPerc    = '';
            % Randomly select charging power for on-road charging event
            pwrChoices = [22, 50, 75, 150];
            idx = randi(numel(pwrChoices));
            pwrRoad = pwrChoices(idx);
            if pwrRoad == 22
                pwrStr = sprintf('AC_%dkW', pwrRoad);
            else
                pwrStr = sprintf('DC_%dkW', pwrRoad);
            end
        
            chgRoad = "Yes_" + pwrStr;  % Set charge flag and charger type
        
            % Calculate additional charge needed for the distance over full range
            overDist   = abs(totalDist - range);                 % "Extra" km
            overCap    = (use * overDist)/1000;                  % kWh for over distance
            timeRoad   = overCap * (1 + charloss/100) / pwrRoad; % Time to charge on the road
            % Add time for topping up to desired SoC at end
            timeToFull=timeRoad+(usedCap-overCap - capFull*(1 - SOC/100)) * (1 + charloss/100) / pwr;
          end
        
          %--- Convert charging times to "h min" format
          hRoad = floor(timeRoad);
          mRoad = round(mod(timeRoad, 1) * 60);
          hchg = floor(timeToFull);
          mchg = round(mod(timeToFull, 1) * 60);
        
          %--- Fill output struct for this day's profile
          P.(day) = struct( ...
            'Purpose',          purpose, ...
            'Day',              days{d}, ...
            'Temperature',         tempRandom, ...
            'Consumption',     use, ...
            'FullCapacity',      capFull, ...
            'CapacityWithTemperatur', cap, ...
            'PercentOperatingCapacity',    capTemp, ...
            'FullRange',         rangeFull, ...
            'RangeWithTemperatur',    range, ...
            'PercentOperatingRange',        rangeTemp, ...
            'Distance', totalDist, ...
            'AvgSpeed',          avgspeed, ...
            'ChargingLocation',           loc, ...
            'SoC',             SOC, ...
            'ChargingType', ctype, ...
            'PercentChargingLoss', charloss, ...
            'TripNumber', Ntrip, ...
            'TripStart', startStr, ...
            'TripEnd', endStr, ...
            'RunTime',             sprintf('%dh %dmin', floor(runT), round(mod(runT,1)*60)), ...
            'StopTime',            stopStr, ...
            'ChargeOnRoad',            chgRoad, ...
            'BatteryPerc',            remPerc, ...
            'ChargingTimeOnRoad',         sprintf('%dh %dmin', hRoad, mRoad), ...
            'TotalTimeToCharge',        sprintf('%dh %dmin', hchg, mchg) ...
            );

            
            % Here, fields are formatted nicely for table/export.
            P.(day) = F;
            P.(day).Purpose             = purpose;
            P.(day).Day                 = days{d};
            P.(day).Temperature         = sprintf('%d °C', round(tempRandom));
            P.(day).Consumption         = sprintf('%d Wh/km', round(use));
            P.(day).FullCapacity         = sprintf('%d kWh', round(capFull));
            P.(day).CapacityWithTemperatur = sprintf('%d kWh', round(cap));
            P.(day).PercentOperatingCapacity    = sprintf('%.1f %%', round(capTemp,1));
            P.(day).FullRange         = sprintf('%d km', round(rangeFull));
            P.(day).RangeWithTemperatur    = sprintf('%d km', round(range));
            P.(day).PercentOperatingRange        = sprintf('%.1f %%',round(rangeTemp,1)); 
            P.(day).Distance = sprintf('%d km', round(totalDist));
            P.(day).AvgSpeed          = sprintf('%d km/h',round(avgspeed));
            P.(day).ChargingLocation           = loc;
            P.(day).SoC            = sprintf('%.1f %%',round(SOC));
            P.(day).ChargingType             = ctype;
            P.(day).PercentChargingLoss            = sprintf('%.1f %%',round(charloss,1));
            P.(day).TripNumber            = sprintf('%d trips',Ntrip);
            P.(day).TripStart            = startStr;
            P.(day).TripEnd         = endStr;
            P.(day).RunTime               = sprintf('%dh %dmin', floor(runT), round(mod(runT,1)*60));
            P.(day).StopTime              = stopStr;      
            P.(day).ChargeOnRoad          = chgRoad;
            P.(day).BatteryPerc           = sprintf('%.1f %%', remPerc);
            P.(day).ChargingTimeOnRoad    = sprintf('%dh %dmin', hRoad, mRoad);
            P.(day).TotalTimeToCharge     = sprintf('%dh %dmin', hchg, mchg);
        end
        
          %--- Print results for both days for this simulation round
          myprint(fid, '--- Simulation %d: Workday ---\n', i);
          mydisp(fid, P.Workday);
        
          myprint(fid, '--- Simulation %d: Weekend ---\n', i);
          mydisp(fid, P.Weekend);
        
          myprint(fid, '\n');
        end
    end 