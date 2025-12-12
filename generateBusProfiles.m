function profiles = generateBusProfiles(N, segmentFile, chargingTypesFile, fid)
%GENERATEBUSPROFILES  Generate N bus mobility profile structs and print to file/screen.
%   profiles = generateBusProfiles(N, segmentFile, chargingTypesFile, fid)
%   Reads segmentFile (ev_segments.csv) and chargingTypesFile (chargingCompatible.csv),
%   and returns a 1×N struct array with fields describing the bus mobility profiles.
%   The function also prints each generated profile to the screen and to the file (fid).
%   Each simulation includes both Workday and Weekend trip profiles with realistic logic.
%
%   INPUTS:
%       N                  - number of profiles to generate
%       segmentFile        - filename of EV segment data
%       chargingTypesFile  - filename of compatible charging types
%       fid                - file identifier for output (from fopen)
%
%   OUTPUT:
%       profiles           - struct array with mobility profile information for buses

    %--- Read input segment and compatible charger type data ---
    Tseg   = readEVsegment(segmentFile);
    Ctypes = readChargingCompatible(chargingTypesFile);
    
    %--- Read temperature data for battery derating ---
    opts = detectImportOptions('Temperatur.CSV', 'Delimiter', ',');
    opts.VariableNamingRule = 'preserve';
    T = readtable('Temperatur.CSV', opts);

    %--- Get the overall range of possible temperatures ---
    overallMin = min(T.Temp_from);
    overallMax = max(T.Temp_to);

    %--- Identify the bus segment row in the EV segment data ---
    idx = strcmp(Tseg.Segment, 'Bus');
    capMin = Tseg.NomCap_min(idx);
    capMax = Tseg.NomCap_max(idx);
    rangeMin = Tseg.Range_min(idx);
    rangeMax = Tseg.Range_max(idx); 

    %--- Find compatible charger types for bus ---
    busRow = Ctypes(strcmp(Ctypes.Segment, 'Bus'), :);
    vars = Ctypes.Properties.VariableNames(2:end);
    compatible = vars(busRow{1,2:end});

    %--- Define output struct template for profiles ---
    F = struct( ...
        'Purpose', [], 'Day', [], 'Temperature', [], 'Consumption', [], 'FullCapacity', [], ...
        'CapacityWithTemperatur', [], 'PercentOperatingCapacity', [], 'FullRange', [], ...
        'RangeWithTemperatur', [], 'PercentOperatingRange', [], 'Distance', [], 'AvgSpeed', [], ...
        'ChargingLocation', [], 'ChargingType', [], 'SoC', [], 'PercentChargingLoss', [], ...
        'TripNumber', [], 'TripStart', [], 'TripEnd', [], 'RunTime', [], 'StopTime', [], ...
        'ChargeOnRoad', [], 'ChargingTimeOnRoad', [], 'BatteryPerc', [], 'TotalTimeToCharge', []);
 
    profiles = repmat(F, N, 2);  % Preallocate for all days

    %--- Generate N mobility profiles ---
    for i = 1:N
        %--- Sample a random temperature from the overall temperature range ---
        tempRandom = overallMin + (overallMax - overallMin)*rand();

        %--- Find the row in temperature table that applies to tempRandom ---
        idxLogical = (T.Temp_from <= tempRandom) & (tempRandom <= T.Temp_to);
        idxRow = find(idxLogical, 1, 'first');
        if isempty(idxRow)
            error("No range found for temperature %.2f!", tempRandom);
        end

        %--- Get temperature-affected capacity and range values ---
        capMinTemp   = T.("Capacity_min")(idxRow);
        capMaxTemp   = T.("Capacity_max")(idxRow);
        rangeMinTemp = T.("Range_min")(idxRow);
        rangeMaxTemp = T.("Range_max")(idxRow);
        capTemp   = capMinTemp + (capMaxTemp - capMinTemp)*rand();
        rangeTemp = rangeMinTemp + (rangeMaxTemp - rangeMinTemp)*rand();
        capLoss   = 100 - capTemp;    % percent capacity loss

        %--- Random full battery capacity and range for this bus ---
        capFull   = capMin   + (capMax   - capMin)   * rand;
        rangeFull = rangeMin + (rangeMax - rangeMin) * rand;

        %--- Calculate consumption in Wh/km based on chosen capacity and range ---
        use = capFull * 1000 / rangeFull;

        %--- Compute active capacity and range after temperature derating ---
        cap   = capFull   * capTemp   / 100;    
        range = rangeFull * rangeTemp / 100;

        %--- Select a random compatible charger and extract power ---
        ctype = compatible{ randi(numel(compatible)) };
        pwr = str2double(regexp(ctype, '\d+', 'match', 'once'));

        %--- Determine charging location and state-of-charge (SoC) limit ---
        if startsWith(ctype, 'DC')
            loc = 'Public';
            SOC = 80;
        elseif startsWith(ctype, 'AC')
            SOC = 100;
            loc = locations(randi(2));
        else
            loc = 'Privat';
        end

        %--- Simulation of Workday and Weekend trips for each profile ---
        days = {'Workday', 'Weekend'};
        
        % Generate a feasible total distance for the day (for the bus)
        condDist = false;
        while ~condDist
            % Randomly select the distance per trip between 5 and 25 km
            trip  = 5  + (25 - 5)   * rand();      
        
            % Randomly select an EVEN number of weekday trips between 6 and 14
            % (bus drives multiple times per day)
            Nwork = 2 * randi([3, 7]);             
        
            % Calculate the total daily distance
            totalDist = trip * Nwork;              
        
            % Only accept the distance if it is between 80 and 180 km per day
            % (Constraint: simulates realistic daily driving for buses)
            if totalDist >= 80 && totalDist <= 180
                condDist = true;
            end
        end
        
        % Total time the bus is operating that day (between 5 and 7 hours)
        runT = 5 + (7 - 5)*rand;                  
        
        % Duration of each trip (hours)
        run = runT / Nwork;                       
        
        % Total stop time across the day, random between runT/6 and runT/5 hours
        stopT_work = (runT/6) + (runT/5 - runT/6) * rand();
        
        % Compute latest possible trip start so last trip ends before 3:00am next day
        % (Assuming 27 = 24h + 3h, as time can wrap around midnight)
        latestStart = 27 - (runT + stopT_work);   
        
        % Randomly choose a start time between 4:00 and latest possible start
        if latestStart < 4
            startT = 4;
        else
            startT = 4 + (latestStart - 4) * rand();
        end
        
        purpose = 'Bus';
        
        for d = 1:2
            day = days{d};
            if d == 1
                %--- Workday ---
                Ntrip = Nwork;                           % Use all planned trips for weekday
                stopT = stopT_work;                      % Use precomputed stop time
                stop = stopT / (Ntrip - 1);              % Average stop time between trips
            else
                %--- Weekend (usually fewer trips) ---
                % Choose a smaller EVEN number of trips (at most weekday trips)
                Ntrip = 2 * randi([3, Nwork/2]);
                % New total stop time, random between runT/6 and runT/4 hours
                stopT = (runT/6) + (runT/4 - runT/6) * rand();
                stop = stopT / (Ntrip - 1);
            end
        
            %--- Set up trip timing arrays (start and end times in hours/minutes) ---
            startStr = strings(1, Ntrip);
            endStr = strings(1, Ntrip);
            starts = zeros(1, Ntrip);   % start times (hours since midnight)
            starts(1) = startT;
            ends = zeros(1, Ntrip);
        
            for k = 1:Ntrip
                % Each trip ends after "run" hours from its start
                ends(k) = starts(k) + run;
                h = floor(ends(k));
                m = round(mod(ends(k),1)*60);
                endStr(k) = sprintf('%dh %02dmin', h, m);
                if k < Ntrip
                    % Next trip starts after the previous ends + stop time
                    starts(k+1) = ends(k) + stop;
                end
                h = floor(starts(k));
                m = round(mod(starts(k),1)*60);
                startStr(k) = sprintf('%dh %02dmin', h, m);
            end
            
            %--- Format trip times for output as strings (e.g. "10h 35min")
            startStr = arrayfun(@(x) sprintf('%dh %02dmin', floor(x), round(mod(x,1)*60)), starts,  'Uni',false);
            endStr   = arrayfun(@(x) sprintf('%dh %02dmin', floor(x), round(mod(x,1)*60)), ends,    'Uni',false);
            
            %--- Calculate total distance and average speed for the day ---
            dist = trip * Ntrip;        % total km driven
            avgspeed = dist / runT;     % average speed = total distance / total run time
        
            %--- Charging loss calculation (randomly between 6% and 8%) ---
            % This accounts for energy lost during the charging process.
            charloss = 6 + (8 - 6)*rand;
        
            %--- Calculate energy usage and charging requirement ---
            % usedCap = total energy used that day in kWh (Wh/km * km / 1000)
            usedCap = (use .* totalDist) / 1000;    
        
            % If daily driving distance is less than the (temperature-reduced) range
            if totalDist < (range - 20)
                %--- Enough battery for whole day; may not need to charge on road ---
                % remPerc = percentage of battery remaining after trips, adjusted for temp loss
                remPerc = round((capFull - usedCap - capFull*capLoss/100)*100 / capFull); 
                chgRoad = 'No';                     % No charging needed en route
                timeRoad = 0.0;                     % No charging time on road
        
                % If SoC falls below 80%, simulate charging to replenish to SoC (usually at depot)
                if remPerc < 80
                    currentWh = capFull * (remPerc / 100);    % current battery energy [Wh]
                    targetWh = capFull * SOC/100;             % target SoC in Wh (usually 80%/100%)
                    energyToCharge = targetWh - currentWh; 
                    % timeToFull: charging time in hours, including charging loss
                    timeToFull = energyToCharge * (1 + charloss/100) / pwr;                  
                else
                    timeToFull = 0.0;                         % No charging needed
                end
            else
                %--- Distance exceeds single-charge range; needs charging on road ---
                remPerc = ''; 
                chgRoad = 'Yes';
                overDist = abs(totalDist - range);                % how much further than range
                overCap  = (use .* overDist) / 1000;              % extra kWh needed
                % timeRoad: time to charge the extra required energy, including charging loss
                timeRoad = overCap * (1 + charloss/100) / pwr;
                % timeToFull: charging time needed to refill battery from 20% (as example) up to full
                timeToFull = (usedCap - capFull * 0.2) * (1 + charloss/100) / pwr;
            end
        
            %--- Format charging times into hours/minutes for display ---
            hRoad = floor(timeRoad);
            mRoad = round(mod(timeRoad, 1) * 60);
            hchg = floor(timeToFull);
            mchg = round(mod(timeToFull, 1) * 60);


            %--- Build output struct for this day ---
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
            P.(day).Distance                   = sprintf('%d km', round(dist));
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

        %--- Print each simulated profile for both days to file and screen ---
        myprint(fid, '--- Simulation %d: Workday ---\n', i);
        mydisp(fid, P.Workday);

        myprint(fid, '--- Simulation %d: Weekend ---\n', i);
        mydisp(fid, P.Weekend);

        myprint(fid, '\n');
    end
end