function mydisp(fid, S)
%   MYDISP   Display struct fields to both screen and file, formatted like disp
%   mydisp(fid, S) takes a struct S and prints each field and its value 
%   both to the file given by fid and to the MATLAB command window, using
%   the myprint helper function for consistent formatting.
%
%   Inputs:
%     fid - File identifier (from fopen) to which to write output
%     S   - MATLAB struct whose fields and values are to be displayed
%
%   This function:
%     - Handles cell arrays by converting them to a readable string
%     - Converts numeric values to strings
%     - Uses myprint to print in the form "    FieldName: Value"
%     - Ensures screen and file output are always identical

    % Get all field names from the struct S
    fields = fieldnames(S);

    % Loop through each field in the struct
    for i = 1:numel(fields)
        value = S.(fields{i}); % Get the value for the current field

        % If the field value is a cell array, convert to string representation
        if iscell(value)
            str = '{';
            for j = 1:length(value)
                if j > 1
                    str = [str '  ']; % Add spacing between cell elements
                end
                % Enclose each cell element in single quotes and concatenate
                str = [str '''' char(value{j}) ''''];
            end
            str = [str '}']; % Close the cell array representation
            value = str;     % Use this string for output
        end

        % If the value is numeric, convert to string for printing
        if isnumeric(value)
            value = num2str(value);
        end

        % Print the field name and value, indented for readability
        % Format: 4 spaces, 25-char wide left-justified field name, colon, value
        myprint(fid, '    %-25s: %s\n', fields{i}, value);
    end
end