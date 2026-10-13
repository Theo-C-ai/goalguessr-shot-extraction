function batch_extract_shot_coords()
% BATCH_EXTRACT_SHOT_COORDS  Runs goal_to_pitch_coords on every image in a folder.
%
% Looks for images named goalNNN.jpg, .jpeg, .png or .bmp (for example
% goal001.jpg) in the "Images_for_MATLAB" folder next to this script, runs
% the guided calibration on each one in number order, and appends the
% results to shot_coordinates.txt as: filename <tab> x <tab> y (metres).
%
% Images already listed in shot_coordinates.txt are skipped, so you can stop
% and resume at any time. Choose STOP in the landmark dialog to quit cleanly.

scriptDir = fileparts(mfilename('fullpath'));
imagesDir = fullfile(scriptDir, "Images_for_MATLAB");
outFile   = fullfile(scriptDir, "shot_coordinates.txt");

if ~isfolder(imagesDir)
    error("Images folder not found: %s", imagesDir);
end

% ---- Find all goalNNN.ext images, no hard-coded upper bound ----
d = dir(fullfile(imagesDir, "goal*.*"));
validExt = [".jpg", ".jpeg", ".png", ".bmp"];
entries = struct("name", {}, "num", {});

for i = 1:numel(d)
    [~, base, ext] = fileparts(d(i).name);
    if ~any(strcmpi(ext, validExt))
        continue;
    end
    tok = regexp(base, '^goal(\d+)$', 'tokens', 'ignorecase');
    if isempty(tok)
        continue;
    end
    entries(end+1) = struct("name", d(i).name, "num", str2double(tok{1}{1})); %#ok<AGROW>
end

if isempty(entries)
    error("No goalNNN.* images found in %s", imagesDir);
end

[~, order] = sort([entries.num]);
entries = entries(order);
fprintf("Found %d images: goal%03d ... goal%03d\n", numel(entries), ...
    entries(1).num, entries(end).num);

% ---- Work out which images are already done (resume support) ----
alreadyDone = strings(0);
if isfile(outFile)
    fid = fopen(outFile, "r");
    line = fgetl(fid);
    if ischar(line) && startsWith(line, "filename")
        line = fgetl(fid);
    end
    while ischar(line)
        parts = strsplit(line, "\t");
        if ~isempty(parts)
            alreadyDone(end+1) = string(parts{1}); %#ok<AGROW>
        end
        line = fgetl(fid);
    end
    fclose(fid);
end

% ---- Open the output file in append mode, write the header if it is new ----
writeHeader = ~isfile(outFile);
fid = fopen(outFile, "a");
if writeHeader
    fprintf(fid, "filename\tx\ty\n");
end

% ---- Main loop ----
nTotal = numel(entries);
for i = 1:nTotal
    name = entries(i).name;
    if any(alreadyDone == string(name))
        fprintf("[%d/%d] Skipping %s (already in output file)\n", i, nTotal, name);
        continue;
    end

    fprintf("\n[%d/%d] Calibrating %s ...\n", i, nTotal, name);
    try
        [shotXY, name] = goal_to_pitch_coords(name);
        fprintf(fid, "%s\t%.3f\t%.3f\n", name, shotXY(1), shotXY(2));
        fprintf("  -> logged x=%.2f, y=%.2f\n", shotXY(1), shotXY(2));
    catch ME
        if strcmp(ME.identifier, "goalguessr:userStop")
            fprintf("Stopped by user.\n");
            close all;
            break;
        end
        warning("Skipped %s: %s", name, ME.message);
    end
    close all; % clear figures before the next image
end

fclose(fid);
fprintf("\nDone. Results written to %s\n", outFile);
end