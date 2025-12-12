function T = readTemperature(temperatureFile)
%READTEMPERATURE  Read the temperature CSV file into a MATLAB table
%   T = readTemperature(temperatureFile) reads the CSV file specified by
%   temperatureFile and returns a table T with all the original columns.
%
%   INPUT:
%     temperatureFile - filename (char or string) of the temperature CSV file
%
%   OUTPUT:
%     T - MATLAB table containing all columns from the temperature CSV

    % Detect import options for the CSV file, specifying comma as the delimiter,
    % and preserve the original column names from the CSV (including special characters)
    opts = detectImportOptions('Temperatur.CSV', 'Delimiter', ',');
    opts.VariableNamingRule = 'preserve';
    
    % Read the CSV file into a table using the detected options.
    % This will automatically handle headers, datatypes, and missing values.
    T = readtable(temperatureFile, opts);
end