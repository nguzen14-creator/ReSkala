function T = readEVsegment(carFile)
%   READEVSEGMENTS  Read the EV‐segments CSV into a table
%   T = readEVSegments(carFile) reads the CSV named by filename
%   and returns a MATLAB table with all columns.

    % Use readtable (handles headers and mixed types automatically)
    T = readtable(carFile, 'TextType', 'string');  
end