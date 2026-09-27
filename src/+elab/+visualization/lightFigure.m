function f = lightFigure(position)
% lightFigure  Create a hidden figure with a reproducible light theme.
%
%   f = elab.visualization.lightFigure()
%   f = elab.visualization.lightFigure(position)

    arguments
        position (1,4) double = [100 100 900 460]
    end

    f = figure("Visible", "off", "Position", position);
    if isprop(f, "Theme")
        theme(f, "light");
    end
end
