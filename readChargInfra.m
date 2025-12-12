function T = readChargInfra(fname)
%READLCHARGINFRA  Read the chargingStation CSV into a table
%   T = readChargInfra(fname) reads the charging infrastructure CSV file given
%   by fname and returns a table T with all columns and original names.
%   It also handles missing values and ensures logical (boolean) columns are
%   imported as logicals rather than numbers or strings.
%
%   Input:
%       fname - filename (string or char) of the CSV file to read
%   Output:
%       T     - MATLAB table with all charging infrastructure data

    %--- Detect import options for the CSV, preserving the original column names
    optsCS = detectImportOptions(fname,'VariableNamingRule','preserve');
    % Set all variables to treat '' (empty string) and 'NA' as missing values
    optsCS = setvaropts(optsCS, optsCS.VariableNames, 'TreatAsMissing', {'', 'NA'});
    % (Note: You can customize missing value handling if necessary.)

    %--- Read the table using the above options
    T = readtable(fname, optsCS);

    %--- Post-processing: Convert columns named 'Private' and 'Public' to logicals
    %   (Some CSVs store logicals as 'TRUE'/'FALSE', or 1/0, or strings/cells.)

    % Check if 'Private' column exists
    if ismember("Private", T.Properties.VariableNames)
        col = T.Private;
        % If it's cell array, convert from 'TRUE'/'FALSE' strings
        if iscell(col)
            T.Private = strcmpi(col, 'TRUE');
        % If it's a string array, compare with "TRUE"
        elseif isstring(col)
            T.Private = col == "TRUE";
        end
        % If numeric, will already be 0/1 (no action needed)
    end

    % Check if 'Public' column exists
    if ismember("Public", T.Properties.VariableNames)
        col = T.Public;
        if iscell(col)
            T.Public = strcmpi(col, 'TRUE');
        elseif isstring(col)
            T.Public = col == "TRUE";
        end
    end
end