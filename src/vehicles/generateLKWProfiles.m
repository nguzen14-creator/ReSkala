function profiles = generateLKWProfiles(purposes, segmentFile, chargingTypesFile, fid)
%GENERATELKWPROFILES  Generate LKW (truck) mobility profiles for each purpose
%   profiles = generateLKWProfiles(purposes, segmentFile, chargingTypesFile, fid)
%   Generates detailed mobility/charging profiles for each LKW purpose, for both
%   workday and weekend, and prints the formatted output to file/screen.
%
%   Input:
%     purposes           -- cell array or string array of LKW types ("LKW (over 7.5t)" etc.)
%     segmentFile        -- filename of vehicle segment CSV (e.g. 'ev_segments.csv')
%     chargingTypesFile  -- filename of charging compatibility CSV (e.g. 'chargingCompatible.csv')
%     fid                -- file ID for printing (use 1 for screen)
%
%   Output:
%     profiles           -- [N x 2] struct array of profile details (not used in print)

  % --- Read EV segment specification table and charging compatibility table
  Tseg   = readEVsegment(segmentFile);
  Ctypes = readChargingCompatible(chargingTypesFile);
  
  % --- Read the temperature effect table (capacity/range losses), preserving column names
  opts = detectImportOptions('Temperatur.CSV', 'Delimiter', ',');
  opts.VariableNamingRule = 'preserve';
  T = readtable('Temperatur.CSV',opts);

  % --- Get the minimum and maximum operating temperature from table
  overallMin = min(T.Temp_from);
  overallMax = max(T.Temp_to);

  N = length(purposes);   % Number of different LKW profiles to generate

  for i = 1:N
      % --- Select the current LKW type/purpose
      purpose = purposes(i);

      % --- Find compatible charger types (e.g. AC/DC, 22kW, etc) for this LKW
      pkwRow = Ctypes(strcmp(Ctypes.Segment,purpose), :);
      vars = Ctypes.Properties.VariableNames(2:end);
      compatible = vars( pkwRow{1,2:end} );

      % --- Extract the row from vehicle segment table for this LKW
      idx = strcmp(Tseg.Segment, purpose);

      % --- Pull battery size, range, average speeds for this LKW
      capMin = Tseg.NomCap_min(idx);
      capMax = Tseg.NomCap_max(idx);
      rangeMin = Tseg.Range_min(idx);
      rangeMax = Tseg.Range_max(idx);
      v_urban = Tseg.AvgSpd_urban(idx);
      v_rural = Tseg.AvgSpd_rural(idx);
      v_highway  = Tseg.AvgSpd_highway(idx);

      % --- Draw a random outside temperature within the table's range
      tempRandom = overallMin + (overallMax - overallMin)*rand();
      idxLogical = (T.Temp_from <= tempRandom) & (tempRandom <= T.Temp_to);
      idxRow = find(idxLogical, 1, 'first');
      if isempty(idxRow)
          error("No range found for temperature %.2f!", tempRandom);
      end

      % --- For this temperature, get min/max capacity and range loss factors
      capMinTemp   = T.("Capacity_min")(idxRow);
      capMaxTemp   = T.("Capacity_max")(idxRow);
      rangeMinTemp = T.("Range_min")(idxRow);
      rangeMaxTemp = T.("Range_max")(idxRow);

      % --- Randomly pick the effective (temperature-adjusted) capacity and range (%)
      capTemp = capMinTemp + (capMaxTemp - capMinTemp)*rand();
      rangeTemp    = rangeMinTemp + (rangeMaxTemp - rangeMinTemp)*rand();
      capLoss   = 100 - capTemp;    % percent capacity loss

      % --- Random full battery capacity and range (pick a model within segment)
      capFull   = capMin   + (capMax   - capMin)   * rand;
      rangeFull = rangeMin + (rangeMax - rangeMin) * rand;

      % --- Compute actual available battery and range at temperature
      cap   = capFull   * capTemp   / 100;    
      range = rangeFull * rangeTemp / 100;

      % --- Random energy usage, in Wh/km (based on full battery/range)
      use = capFull * 1000 / rangeFull; 

      % --- Randomly select a compatible charger for this vehicle
      ctype = compatible{ randi(numel(compatible)) };
      % --- Extract charger power (kW) from the name string (handles decimals)
      pwr = str2double( regexp(ctype,'\d+(\.\d+)?','match','once') );

      % --- Set charging location and SOC (target charge) based on charger type
      if startsWith(ctype,'DC')
        loc = 'Public';
        SOC = 80;
      elseif startsWith(ctype,'AC')
        SOC = 100;
        loc = locations(randi(2));
      else
         loc = 'Privat'; 
      end

      % --- Output struct template for this profile (holds all info fields)
      F = struct( ...
        'Purpose', [],'Day',[],'Temperature', [],'Consumption', [],'FullCapacity', [], ...
        'CapacityWithTemperatur',[] ,'PercentOperatingCapacity', [],'FullRange', [], ...
        'RangeWithTemperatur',[],'PercentOperatingRange', [],'Distance', [],'AvgSpeed', [], ...
        'ChargingLocation', [],'ChargingType', [], 'SoC' , [],'PercentChargingLoss',[], ...
        'TripNumber', [], 'TripStart', [], 'TripEnd', [],'RunTime', [],'StopTime', [], ...
        'ChargeOnRoad',[],'ChargingTimeOnRoad',[],'BatteryPerc', [], 'TotalTimeToCharge', [] );
   
      profiles = repmat(F, N, 2); % (not used in printed output)
      
      % --- Weekday/Weekend simulation
      days = {'Workday','Weekend'};
      startT = rand * 24;    % Random start time for first trip (0–24h)
      Nwork = randi([2,4]);  % Random number of trips on workday (2–4)
      
      for d = 1:2
          day = days{d};      
          if d == 1
            Ntrip = Nwork;             % Workday: Nwork trips
          else
            % Weekend: random between 2 and Nwork (inclusive)
            Ntrip = randi([2, Nwork]);
          end
     
          % --- Generate realistic trip and stop schedule for this day
          valid = false;
          while ~valid
               % Each trip: random running time between 1 and 4 hours
               run = 1 + (4-1)*rand(1, Ntrip);    
               runT = sum(run);      % total running time
               nStop = Ntrip - 1;    % number of stops between trips
               stop = 0.3 + (1.5-0.3)*rand(1, nStop); % stop times between 0.3 and 1.5 hours
               stopT = sum(stop);     
               totalTime = runT + stopT;
               % Valid if runT in [3,7]h and total window [4,10]h
               valid = (runT >= 3) && (runT <= 7) && (totalTime >= 4) && (totalTime <= 10);
           end
            
           % --- Schedule trip start/end times (wrap around 24h)
           startStr = strings(1, Ntrip);  % Preallocate array to hold trip start time strings (e.g., '15h 40min')
           endStr = strings(1, Ntrip);    % Preallocate array to hold trip end time strings
            
           starts = zeros(1, Ntrip);      % Will hold trip start times (in hours since midnight, e.g., 15.67)
           starts(1) = startT;            % The first trip starts at the random "startT" (in hours)
            
           ends = zeros(1, Ntrip);        % Will hold trip end times (in hours since midnight, e.g., 17.23)
           for k = 1:Ntrip
               % --- Calculate trip end time, allowing it to wrap around the 24h clock
               ends(k) = mod(starts(k) + run(k),24);   % Each trip lasts "run(k)" hours
           
               % --- Format end time as 'Hh MMmin'
               h = floor(ends(k));                        % Extract whole hours
               m = round(mod(ends(k),1)*60);              % Get remaining minutes
               endStr(k) = sprintf('%dh %02dmin', h, m);  % Format as '15h 40min'
           
               % --- Prepare for next trip's start time, also wrapping at 24h
               if k < Ntrip
                    starts(k+1) = mod(ends(k) + stop(k),24);  % Next start: after this trip ends + stop time
               end
            
               % --- Format start time as 'Hh MMmin'
               h = floor(starts(k));
               m = round(mod(starts(k),1)*60);
               startStr(k) = sprintf('%dh %02dmin', h, m);   % E.g., '16h 05min'
            end
            
            % --- Randomly assign road type percentages for today:
            %     - Highway: 61% +/- 5% (i.e., random value between 56 and 66)
            %     - Rural:   25% +/- 5% (i.e., random value between 20 and 30)
            %     - Urban:   remainder to 100%
            highway  =  61 + (rand * 10 - 5);     % 61 + [-5, +5] = [56, 66]
            rural    =  25 + (rand * 10 - 5);     % 25 + [-5, +5] = [20, 30]
            urban    =  100 - highway - rural;    % Urban gets the remainder
           
            % --- Calculate total distance driven today for each road type:
            %     Multiply total running time (all trips) by average speed and road fraction
            highDist   = v_highway * runT * highway/100;    % Highway distance in km
            ruralDist  = v_rural   * runT * rural/100;      % Rural distance in km
            urbanDist  = v_urban   * runT * urban/100;      % Urban distance in km
            
            totalDist = highDist + ruralDist + urbanDist;   % Total distance today (km)

            %--- Format trip times for output as strings (e.g. "10h 35min")
            startStr = arrayfun(@(x) sprintf('%dh %02dmin', floor(x), round(mod(x,1)*60)), starts,  'Uni',false);
            endStr   = arrayfun(@(x) sprintf('%dh %02dmin', floor(x), round(mod(x,1)*60)), ends,    'Uni',false);         
            
            % --- Calculate average speed for the day (total distance / total running time)
            avgspeed = totalDist / runT;
            
            % --- Assign a random charging loss percentage for today (between 6% and 8%)
            charloss = 6 + (8 - 6)*rand;
            
            % --- Charging time calculation ---
            % --- Compute the total battery capacity used for today's distance (in kWh)
            usedCap = (use .* totalDist) / 1000;       % use [Wh/km], totalDist [km] -> usedCap [kWh]
            
            if totalDist < (range - 20)
                % --- Case 1: All trips can be completed without *on-road* charging
                remPerc = round((capFull - usedCap - capFull*capLoss/100)*100/ capFull); 
                % remPerc: remaining battery percent at the end of the day.
                % Formula: 100 * (full capacity - capacity used - capacity lost to temp) / full capacity
            
                chgRoad = 'No';             % No on-road charging required
                timeRoad = 0.0;             % No time spent charging on the road
            
                if remPerc < 80
                    % --- End-of-day battery is low; need to recharge (at home/depot)
                    currentWh = capFull * (remPerc / 100);  % Current energy in battery [kWh]
                    targetWh = capFull * SOC/100;           % Target energy after charge [kWh]
                    energyToCharge = targetWh - currentWh;  % Amount to refill [kWh]
                    timeToFull = energyToCharge * (1 + charloss/100) / pwr; % Charging time incl. losses
                else
                    % --- If >80% left, charging time is zero
                    timeToFull = 0.0;
                end
            else
                % --- Case 2: Today's trips exceed vehicle's maximal range, on-road charging required
                remPerc    = '';
                pwrChoices = [50, 75, 150, 300];
                idx = randi(numel(pwrChoices));
                pwrRoad = pwrChoices(idx);
                pwrStr = sprintf('DC_%dkW', pwrRoad);
                chgRoad = "Yes_" + pwrStr;  % charging on the road
                % --- Calculate "over distance": how much further the trips go than the maximal range
                overDist   = abs(totalDist - range);
                overCap    = (use * overDist) / 1000;% Used capacity exceeds capacity limit in kW
                
                % --- On-road charging time (for the over distance), including charging losses
                timeRoad   = overCap * (1 + charloss/100) / pwrRoad;% charging time on the road 

                % --- Total charging time to reach 80% capacity (may be split between on-road and depot)
                timeToFull = timeRoad + (usedCap - overCap - capFull * 0.2) * (1 + charloss/100) / pwr;
            end
            
            % --- Format output as hours and minutes for both on-road and total charging time
            hRoad = floor(timeRoad);
            mRoad = round(mod(timeRoad, 1) * 60);
            hchg = floor(timeToFull);
            mchg = round(mod(timeToFull, 1) * 60);

           % --- Fill the output struct for this day, all fields formatted
           P.(day) = F;
           P.(day).Purpose                    = purpose;
           P.(day).Day                        = days{d};
           P.(day).Temperature                = sprintf('%d °C', round(tempRandom));
           P.(day).Consumption                = sprintf('%d Wh/km', round(use));
           P.(day).FullCapacity               = sprintf('%d kWh', round(capFull));
           P.(day).CapacityWithTemperatur     = sprintf('%d kWh', round(cap));        
           P.(day).PercentOperatingCapacity   = sprintf('%.1f %%', round(capTemp,1));
           P.(day).FullRange                  = sprintf('%d km', round(rangeFull));
           P.(day).RangeWithTemperatur        = sprintf('%d km', round(range));
           P.(day).PercentOperatingRange      = sprintf('%.1f %%',round(rangeTemp,1));
           P.(day).Distance                   = sprintf('%d km', round(totalDist));
           P.(day).AvgSpeed                   = sprintf('%d km/h',round(avgspeed));
           P.(day).ChargingLocation           = loc;
           P.(day).SoC                        = sprintf('%.1f %%',round(SOC));
           P.(day).ChargingType               = ctype; 
           P.(day).PercentChargingLoss        = sprintf('%.1f %%',round(charloss,1));
           P.(day).TripNumber                 = sprintf('%d trips',Ntrip);
           P.(day).TripStart                  = startStr;
           P.(day).TripEnd                    = endStr;
           P.(day).RunTime                    = sprintf('%dh %dmin', floor(runT), round(mod(runT,1)*60));
           P.(day).StopTime                   = sprintf('%dh %dmin', floor(stopT), round(mod(stopT,1)*60));      
           P.(day).ChargeOnRoad               = chgRoad;
           P.(day).BatteryPerc                = sprintf('%.1f %%', remPerc);
           P.(day).ChargingTimeOnRoad         = sprintf('%dh %dmin', hRoad, mRoad);
           P.(day).TotalTimeToCharge          = sprintf('%dh %dmin', hchg, mchg);
      end

      % --- Print simulation for this profile to file/screen
      myprint(fid, '--- Simulation %d: Workday ---\n', i);
      mydisp(fid, P.Workday);

      myprint(fid, '--- Simulation %d: Weekend ---\n', i);
      mydisp(fid, P.Weekend);

      myprint(fid, '\n');

  end
end











  