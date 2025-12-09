function S = aggregateVehicleTypes(EV)
%   AGGREGATEVEHICLETYPES  Summarize segment info into broad vehicle types
%   S = aggregateVehicleTypes(EV) groups all vehicle segments in table EV
%   into four main types: PKW, Van, LKW, and Bus. It then sums up the
%   quantities and shares for each group and returns a summary table S.
%
%   Input:
%     EV - Table with at least columns 'Segment', 'Quantity', and 'Percentage'
%
%   Output:
%     S  - Summary table with columns 'VehicleType', 'Quantity', 'Percentage'
%
%   Example:
%     >> T = readEVsegment('ev_segments.csv');
%     >> S = aggregateVehicleTypes(T);

    % Define segment groupings for each broad vehicle type
    groups = { ...
        ["Minis","Kleinwagen","Kompaktklasse","Mittelklasse", ...
         "Obere Mittelklasse","Oberklasse","SUV"], ...   % PKW group
        "Van", ...                                       % Van group
        ["LKW (under 7.5t)","LKW (over 7.5t)"], ...      % LKW group
        "Bus" };                                         % Bus group

    % Define the corresponding broad vehicle type names
    names = ["PKW","Van","LKW","Bus"];

    % Preallocate arrays for counts and shares
    counts = zeros(4,1);
    shares = zeros(4,1);

    % Loop over each vehicle type group
    for k = 1:4
        % Find which rows of EV.Segment belong to the current group
        m = ismember(EV.Segment, groups{k});
        % Sum up quantities and percentages for this group
        counts(k) = sum(EV.Quantity(m));
        shares(k) = sum(EV.Percentage(m));
    end

    % Create the summary table
    S = table(names', counts, shares, ...
              'VariableNames',{'VehicleType','Quantity','Percentage'});
end