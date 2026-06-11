function [exp,conf,fitindex,DFA_x,DFA_y] = fastdfa(data,srate,varargin)

% function [exp conf fitindex DFA_x DFA_y] = fastdfa(data,srate,varargin)
%   Vectorised DFA -- drop-in replacement for dfa.m, same interface.
%   Speedups over dfa.m:
%     1. Inner window loop replaced by a single matrix multiply per window
%        size: detrending projection Q is precomputed once per window size
%        and applied to all windows x channels simultaneously.
%     2. Regression loop replaced by a single mldivide over all channels.
%
%   determine the DFA scaling exponent for each column of data
%   input:
%   - data: columns of signals
%   - srate: sampling frequency
%   - varargin:
%     o overlap: proportion overlap between adjacent windows (def = .5)
%     o window: [min max] size of the minimum and maximum window size in
%       seconds (def=[1 20])
%     o plot: (0/1) plot the resulting regression (def=0)
%     o fit: ('R2','RMS') return R2 and RMS deviation as
%       fitindex, as well as the regression data points.
%     o 'noise': matrix of identically filtered (white) noise signals of
%       the same length as data that will be used to correct the final DFA
%       regression.
%     o 'logbins': Number of windows PER DECADE on the time scale. Default 10.
%
% output:
% - exp:      DFA exponents of each signal (1 x NSignals)
% - conf:     95% confidence interval half-width (1 x NSignals)
% - fitindex: struct with R2, RMS, DataX, DataY
% - DFA_x:   log10(window sizes in samples)
% - DFA_y:   log10(RMS fluctuations)
%
% BASED ON ORIGINAL SCRIPT PROVIDED BY K.LINKENKAER-HANSEN

overlap  = 0.5;
window   = [1 20];
doplot   = 0;
fittype  = 'r2'; %#ok<NASGU>
noise    = [];
logbins  = 10;

for v = 1:2:length(varargin)
    switch lower(varargin{v})
        case 'overlap',  overlap = varargin{v+1};
        case 'window',   window  = varargin{v+1};
        case 'plot',     doplot  = varargin{v+1};
        case 'fit',      fittype = varargin{v+1}; %#ok<NASGU>
        case 'noise',    noise   = varargin{v+1};
        case 'logbins',  logbins = varargin{v+1};
    end
end

if size(data,1) < size(data,2)
    warning('fastdfa.m: Are the data in columns?')
end

if nargout > 2
    fitindex = struct;
end

NSignals = size(data,2);
NSamples = size(data,1);

% normalise if noise correction requested
if ~isempty(noise)
    if size(noise,1) ~= NSamples
        error('Noise and data matrices must have the same number of rows')
    end
    noise = Normalize(noise);
    data  = Normalize(data);
end

% log-linear window sizes
d1      = floor(log10(window(1)*srate));
d2      = ceil( log10(window(2)*srate));
DFA_x_t = round(logspace(d1, d2, (d2-d1)*logbins));
DFA_x   = DFA_x_t(DFA_x_t >= window(1)*srate & DFA_x_t <= window(2)*srate);
nBins   = length(DFA_x);

% preprocess: demean + cumsum
y = cumsum(detrend(data, 'constant'));   % NSamples x NSignals

% initialise output
DFA_y = zeros(nBins, NSignals);

% ---- main loop over window sizes ----------------------------------------
for i = 1:nBins
    w = DFA_x(i);

    % detrending projection matrix Q = I - A*pinv(A), precomputed once per
    % window size and reused for every window position and every channel
    t = (1:w)' / w;
    A = [t, ones(w,1)];
    Q = eye(w) - A * (A \ eye(w));      % w x w

    % window start positions (same logic as dfa.m)
    step         = max(1, round(w*(1-overlap)));
    StartSamples = round(linspace(1, NSamples-w+1, ...
                         length(1:step:NSamples-w+1)));
    NWin = length(StartSamples);

    if NWin == 0
        DFA_y(i,:) = nan;
        continue
    end

    % index matrix: w x NWin -- each column is one window's sample indices
    row_idx = bsxfun(@plus, (0:w-1)', StartSamples);   % w x NWin

    % extract all windows for all channels at once: w x NWin x NSignals
    wins = reshape(y(row_idx(:), :), w, NWin, NSignals);

    % detrend all windows x channels with a single matrix multiply
    det = Q * reshape(wins, w, NWin * NSignals);        % w x (NWin*NSignals)
    det = reshape(det, w, NWin, NSignals);

    % RMS over samples, then mean over windows
    DFA_y(i,:) = squeeze(mean(sqrt(mean(det.^2, 1)), 2))';
end

% ---- noise correction ---------------------------------------------------
if ~isempty(noise)
    [~, ~, NoiseFit] = fastdfa(noise, srate, ...
        'overlap', overlap, 'window', window, 'plot', 0, 'fit', 'r2');
end

% ---- vectorised regression over all channels at once --------------------
X_reg = [ones(nBins,1), log10(DFA_x')];    % nBins x 2

if ~isempty(noise)
    Y_all = log10(DFA_y ./ mean(NoiseFit.DataY, 2));
else
    Y_all = log10(DFA_y);                   % nBins x NSignals
end

beta = X_reg \ Y_all;                      % 2 x NSignals
exp  = beta(2,:);

% confidence intervals (equivalent to what regress() returns per channel)
n      = nBins;
resid  = Y_all - X_reg * beta;
s2     = sum(resid.^2, 1) ./ (n - 2);                  % 1 x NSignals
XtXinv = inv(X_reg' * X_reg);
conf   = tinv(0.975, n-2) * sqrt(s2 * XtXinv(2,2));

if nargout > 2
    fitindex.R2    = 1 - sum(resid.^2,1) ./ sum((Y_all - mean(Y_all,1)).^2, 1);
    fitindex.RMS   = sqrt(s2);
    fitindex.DataX = log10(DFA_x ./ srate);
    fitindex.DataY = Y_all;
end

% ---- optional plot -------------------------------------------------------
if doplot
    figure; hold on
    plot(log10(DFA_x./srate), Y_all, 'ko');
    lsline
    grid on; zoom on
    axis([log10(min(DFA_x./srate))-0.1  log10(max(DFA_x./srate))+0.1 ...
          min(Y_all(:))-0.1              max(Y_all(:))+0.1])
    xlabel('log_{10}(time) [s]', 'Fontsize', 12)
    ylabel('log_{10} F(time)',   'Fontsize', 12)
    axis equal
end

% ---- nargout aliases ----------------------------------------------------
if nargout >= 4, DFA_x = log10(DFA_x); end
if nargout >= 5, DFA_y = Y_all;        end

end % function fastdfa
