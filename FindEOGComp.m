function [EOGCompNum EOGCompR OutR] = FindEOGComp(InEEG, EOGChanData, MinR, varargin)
% FinEOGComp: takes EEG data (InEEG), runs ICA when components not 
%   available and compares the components to EOG data provided (EOGChanData)
%   from the same or another dataset. The component which correlates
%   highest is selected, but the correlation must be minimally 'MinR'
% 
%   InEEG:       Input EEG structure
%   EOGChanData: EOG channel data (single row). If empty ([]) then the
%                function will search for EOGH, EOGV, HEOG or VEOG channel
%                labels and use these.
%   MinR:        Critical correlation value
%   
%   varargin
%     - 'extract': ('single','multiple') extract one or multiple values
%       that exceed the crtical R value. default single.

if nargin<3
    MinR = .5;
end
if nargin<2
    error('Must supply EEG struct and EOG data')
end

multiple=0;
for v=1:2:length(varargin)
    if strcmpi(varargin{v},'extract')
        if strcmpi(varargin{v+1},'single')
            multiple=0;
        else
            multiple=1;
        end
    end
end

EOGCompNum = 0;
EOGCompR = 0;

if isempty(InEEG.icaweights)
    error('Must run ica first');
end


% calculate component activations
act = icaact(InEEG.data(:,:),InEEG.icaweights*InEEG.icasphere);


% look up EOG channel data
if isempty(EOGChanData)
    ndx = FindSetNdx({InEEG.chanlocs(:).labels},{'EOGH','EOGV','HEOG','VEOG'});
    if isempty(ndx)
        error('toolbox:dirk:FindEOGComp: Could not locate EOG channels.')
    end
    EOGChanData = InEEG.data(ndx,:);
end


% do the correlations
OutR = corr(act', EOGChanData(:,:)');
if ~multiple
    [EOGCompR EOGCompNum] = max(abs(OutR));
    EOGCompR(EOGCompR<MinR) = 0;
    EOGCompNum(EOGCompR<MinR) = 0;
else
    for comp=1:size(act,1)
        for eog=1:size(EOGChanData,1)
            if abs(R(comp,eog))>=MinR
                EOGCompNum{eog} = union(EOGCompNum{eog},comp);
                EOGCompR{eog} = union(EOGCompR{eog},R(comp,eog));
            end
        end
    end
end
    
