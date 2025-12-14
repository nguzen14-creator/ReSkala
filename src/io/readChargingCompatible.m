function T = readChargingCompatible(fname)
%READCHARGINGCOMPATIBLE  Load charging_types.csv and convert T/F text to logicals.
%   T = readChargingCompatible(fname) returns a table T with the first column
%   “Segments” plus logical columns for each charge-power category.
%
%   INPUT:
%      fname - Filename (char or string) of the CSV file to import
%
%   OUTPUT:
%      T     - MATLAB table with first column “Segments” (type of vehicle)
%              and all other columns as logicals (true/false)

    % 1) Import with original headers
    %    - detectImportOptions gets the import configuration for the CSV file
    %    - 'VariableNamingRule','preserve' ensures original column names are kept (including special characters)
    opts = detectImportOptions(fname);
    opts.VariableNamingRule = 'preserve';
    %    - readtable actually reads the CSV file into a MATLAB table
    T = readtable(fname, opts);

    % 2) Convert any “True”/“False” cell- or string columns to logical
    %    - vars stores all column (variable) names of the table
    vars = T.Properties.VariableNames;
    %    - for loop starts at 2, so first column (Fahrzeugtyp) is skipped (it’s not logical)
    for i = 2:numel(vars)           % skip the first column (Fahrzeugtyp)
        col = T.(vars{i});          % grab current column from table
        if iscell(col)
            % If the column is a cell array (e.g., cellstr from text), compare each entry to 'True'
            T.(vars{i}) = strcmpi(col, 'True'); % returns logical array
        elseif isstring(col)
            % If the column is a string array, compare directly to "True"
            T.(vars{i}) = col == "True";        % returns logical array
        end
        % If already logical or numeric (0/1), no conversion is needed
    end
end