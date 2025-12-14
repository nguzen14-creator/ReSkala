function Allocation = allocateProfiles(Summary, N)
%ALLOCATEPROFILES  Allocate profile counts to vehicle types according to share
%   Allocation = allocateProfiles(Summary, N) distributes a total of N profiles
%   among the vehicle types specified in Summary.VehicleType, proportionally to
%   their share in Summary.Percentage. Ensures at least one profile per type.
%
%   INPUT:
%     Summary - table with columns:
%         VehicleType: string or categorical array of vehicle type names
%         Percentage : numeric vector, share (as percent) of each type
%     N       - integer, total number of profiles to allocate
%
%   OUTPUT:
%     Allocation - table with columns:
%         VehicleType: name of the type
%         Count      : allocated profile count for this type

    % Extract vehicle types and convert percentage shares to fractions
    types  = Summary.VehicleType;
    shares = Summary.Percentage / 100;   % Convert percent to fraction (e.g. 15% -> 0.15)
    M      = numel(shares);              % Number of types

    % Sort shares in ascending order, keep the sorted indices in 'order'
    [~, order] = sort(shares, 'ascend');

    % Initial allocation of profiles to each type (guarantee at least one per type)
    cnt = zeros(M,1);
    for ii = 1:M
        k = order(ii);               % Index into shares/types in ascending order
        raw = shares(k)*N;           % Compute (possibly fractional) expected count for this type
        if raw < 1                   % If less than 1 profile would be assigned
            cnt(k) = 1;              % Assign at least one profile
        else
            cnt(k) = floor(raw);     % Otherwise, assign the integer part
        end
    end

    % Assign any leftover profiles (to reach total N) to the largest-share type
    leftover = N - sum(cnt);         % Compute how many profiles are left to assign
    [~, idxMax] = max(shares);       % Find the index of the type with the largest share
    cnt(idxMax) = cnt(idxMax) + leftover;  % Add the leftovers to that type

    % Build and return the output table
    Allocation = table(types, cnt, ...
                       'VariableNames', {'VehicleType','Count'});
end