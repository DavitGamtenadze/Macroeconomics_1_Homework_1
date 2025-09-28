function logmsg(verbose, msg, varargin)
%LOGMSG Display a formatted message when verbose mode is enabled.

    if ~verbose
        return
    end

    if nargin < 2
        msg = '';
    end

    if isempty(varargin)
        text = msg;
    else
        text = sprintf(msg, varargin{:});
    end

    fprintf('[INFO] %s\n', text);
end
