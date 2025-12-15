# ReSkala – EV Mobility Profiles Generator (MATLAB)

Generate mobility/charging profiles for multiple vehicle types (PKW, Van, LKW, Bus) based on input datasets (vehicle segments, charging infrastructure, charging compatibility).

## Features
- Reads input datasets (CSV/Excel): EV segments, charging infrastructure (kW, losses, etc.), charging compatibility by vehicle type
- Aggregates vehicle segments into 4 main vehicle types (PKW/Van/LKW/Bus)
- Allocates profile counts to vehicle types based on shares
- Generates profiles per vehicle type (PKW, Van, LKW, Bus)
- Exports simulation results to CSV (and prints formatted output to console)
