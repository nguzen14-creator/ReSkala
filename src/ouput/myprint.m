function myprint(fid, varargin)
%   MYPRINT  Print formatted output to a file and to the screen
%   myprint(fid, formatString, ...) uses fprintf to print to a file given by fid,
%   and also prints to the command window. All formatting and arguments should be 
%   passed as additional arguments (varargin), exactly as with fprintf.
%
%   Example:
%     fid = fopen('log.txt', 'w');
%     myprint(fid, 'Result: %.2f\n', 3.14159);
%     fclose(fid);
%
%   This prints "Result: 3.14" both to 'log.txt' and to the MATLAB command window.
%
%   Inputs:
%     fid      - File identifier (from fopen) to which to print
%     varargin - Variable-length input argument list:
%                First argument: format string (as in fprintf)
%                Additional arguments: values to substitute in format string

    % Print the formatted output to the file specified by fid
    fprintf(fid, varargin{:});

    % Print the same formatted output to the command window (screen)
    fprintf(varargin{:});
end