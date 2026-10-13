function [shotXY, imageNameOut, tform] = goal_to_pitch_coords(imageNameOrPath)
% GOAL_TO_PITCH_COORDS  Semi-automatic extraction of a shot location from a
% broadcast frame.
%
% You click known pitch landmarks (penalty spot, box corners and so on) in
% the image. The script fits a projective transform from image pixels to
% real pitch coordinates (metres), then you click the ball and its pitch
% position is returned.
%
% The pitch is 105 x 68 m and all images are assumed to be attacking RIGHT
% (flip the image manually if needed). At least 4 visible landmarks are
% required.
%
% Usage:
%   [shotXY, name, tform] = goal_to_pitch_coords("goal001.jpg");
%
% Images are looked up in the "Images_for_MATLAB" folder next to this script
% unless a full path is given. Needs the Image Processing Toolbox.

% --- Pitch constants (metres) ---
PITCH_L = 105;
PITCH_W = 68;
Y_CENTRE = PITCH_W/2;

% --- Standard dimensions (metres) ---
GOAL_HALF   = 7.32/2;
PEN_SPOT_X  = PITCH_L - 11;
BOX_FRONT_X = PITCH_L - 16.5;
SIX_FRONT_X = PITCH_L - 5.5;
BOX_HALF_W  = 40.32/2;
SIX_HALF_W  = 18.32/2;

BOX_Y_LOW  = Y_CENTRE - BOX_HALF_W;
BOX_Y_HIGH = Y_CENTRE + BOX_HALF_W;
SIX_Y_LOW  = Y_CENTRE - SIX_HALF_W;
SIX_Y_HIGH = Y_CENTRE + SIX_HALF_W;

D_RADIUS = 9.15;
dx = BOX_FRONT_X - PEN_SPOT_X;
dy = sqrt(max(0, D_RADIUS^2 - dx^2));
D_Y_LOW  = Y_CENTRE - dy;
D_Y_HIGH = Y_CENTRE + dy;

% --- Load the image ---
imagePath = resolveImagePath(imageNameOrPath);
[~, imgBase, imgExt] = fileparts(imagePath);
imageNameOut = [imgBase imgExt];

I = imread(imagePath);
I = applyExifOrientation(I, imagePath);

% --- Landmarks: name and known pitch position (metres) ---
landmarks = struct( ...
    "name", { ...
    "Goal-line LOWER corner (corner flag)", ...
    "Goal-line UPPER corner (corner flag)", ...
    "Goal post LOWER", ...
    "Goal post UPPER", ...
    "Penalty spot", ...
    "Penalty box goal-line LOWER corner", ...
    "Penalty box goal-line UPPER corner", ...
    "Penalty box front LOWER corner", ...
    "Penalty box front UPPER corner", ...
    "Six-yard box goal-line LOWER corner", ...
    "Six-yard box goal-line UPPER corner", ...
    "Six-yard box front LOWER corner", ...
    "Six-yard box front UPPER corner", ...
    "D meets box (LOW point on box line)", ...
    "D meets box (HIGH point on box line)" ...
    }, ...
    "xy", { ...
    [PITCH_L, 0], ...
    [PITCH_L, PITCH_W], ...
    [PITCH_L, Y_CENTRE - GOAL_HALF], ...
    [PITCH_L, Y_CENTRE + GOAL_HALF], ...
    [PEN_SPOT_X, Y_CENTRE], ...
    [PITCH_L, BOX_Y_LOW], ...
    [PITCH_L, BOX_Y_HIGH], ...
    [BOX_FRONT_X, BOX_Y_LOW], ...
    [BOX_FRONT_X, BOX_Y_HIGH], ...
    [PITCH_L, SIX_Y_LOW], ...
    [PITCH_L, SIX_Y_HIGH], ...
    [SIX_FRONT_X, SIX_Y_LOW], ...
    [SIX_FRONT_X, SIX_Y_HIGH], ...
    [BOX_FRONT_X, D_Y_LOW], ...
    [BOX_FRONT_X, D_Y_HIGH] ...
    } ...
    );

% --- Guided calibration: click each visible landmark ---
figure('Name', ['Calibration - ' imageNameOut], 'NumberTitle', 'off');
imshow(I); hold on;

imgPts = [];
pitchPts = [];

disp(['--- GUIDED CALIBRATION: ' imageNameOut ' ---']);
disp('For each landmark: CLICK it, or choose NOT VISIBLE.');
disp('Minimum 4 visible landmarks required.');

for k = 1:numel(landmarks)
    lm = landmarks(k);

    choice = questdlg( ...
        sprintf("[%s] Landmark %d/%d:\n%s\n\nClick it if visible.", ...
        imageNameOut, k, numel(landmarks), lm.name), ...
        "Landmark", ...
        "CLICK", "NOT VISIBLE", "STOP", ...
        "CLICK");

    if isempty(choice) || strcmp(choice, "STOP")
        error("goalguessr:userStop", ...
            "Calibration stopped by user on %s.", imageNameOut);
    end

    if strcmp(choice, "NOT VISIBLE")
        continue;
    end

    title(['CLICK: ' lm.name], 'Interpreter', 'none');
    [u, v] = ginput(1);

    if isempty(u) || isempty(v)
        continue;
    end

    plot(u, v, 'rx', 'MarkerSize', 10, 'LineWidth', 2);

    imgPts(end+1, :)   = [u v];   %#ok<AGROW>
    pitchPts(end+1, :) = lm.xy;   %#ok<AGROW>

    fprintf("Added %-40s -> pitch(%.2f, %.2f)\n", ...
        lm.name, lm.xy(1), lm.xy(2));
end

if size(imgPts, 1) < 4
    error("Not enough visible landmarks (%d) for %s. Need at least 4.", ...
        size(imgPts, 1), imageNameOut);
end

tform = fitgeotrans(imgPts, pitchPts, 'projective');
fprintf("\nTransform computed using %d landmarks for %s.\n", ...
    size(imgPts, 1), imageNameOut);

% --- Click the ball ---
figure('Name', ['Shot Location - ' imageNameOut], 'NumberTitle', 'off');
imshow(I); hold on;
title(['Click the BALL (or strike point) - ' imageNameOut]);

[uShot, vShot] = ginput(1);
plot(uShot, vShot, 'go', 'MarkerSize', 10, 'LineWidth', 2);

[xShot, yShot] = transformPointsForward(tform, uShot, vShot);
shotXY = [xShot, yShot];

fprintf('--- RESULT (%s) ---\nShot location: x = %.2f m, y = %.2f m\n', ...
    imageNameOut, xShot, yShot);

if xShot < -5 || xShot > (PITCH_L + 5) || yShot < -5 || yShot > (PITCH_W + 5)
    warning("Shot for %s appears outside pitch bounds, calibration may be off.", ...
        imageNameOut);
end

end

function I = applyExifOrientation(I, imagePath)
% Corrects images whose EXIF Orientation tag indicates a rotation or
% mirror that imread() does NOT apply automatically. This is what makes
% MATLAB show a different orientation than Windows, browsers or Photos apps.
try
    info = imfinfo(imagePath);
    if ~isfield(info, 'Orientation') || isempty(info.Orientation)
        return; % no tag, nothing to do
    end
    switch info.Orientation
        case 1
            % normal, do nothing
        case 2
            I = fliplr(I);
        case 3
            I = rot90(I, 2);
        case 4
            I = flipud(I);
        case 5
            I = rot90(fliplr(I), 1);
        case 6
            I = rot90(I, -1);
        case 7
            I = rot90(fliplr(I), -1);
        case 8
            I = rot90(I, 1);
    end
catch
    % if the EXIF read fails (for example a png with no EXIF), skip silently
end
end

function imagePath = resolveImagePath(imageNameOrPath)
% Accepts a full path, or a filename inside Images_for_MATLAB next to this script.
if isfile(imageNameOrPath)
    imagePath = char(imageNameOrPath);
    return;
end

scriptDir = fileparts(mfilename('fullpath'));
candidate = fullfile(scriptDir, 'Images_for_MATLAB', imageNameOrPath);
if isfile(candidate)
    imagePath = char(candidate);
    return;
end

error('Image ''%s'' not found in Images_for_MATLAB.', imageNameOrPath);
end