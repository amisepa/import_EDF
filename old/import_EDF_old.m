%% import_EDF() - imports European Data Formatted (EDF) files: EDF-/EDF+/EDF+C/EDF+D data and converts it to the EEGLAB format
% Works ony with Matlab 2020b or later, AND with Signal processing toolbox installed!
%
% Usage:
%   EEG = import_EDF();             % load EDF file with pop-up window mode
%   EEG = import_EDF(filePath);     %load EDF file with full file name and path provided
%
% Optional inputs:
%   filename  - path and name of .edf file
%
% Outputs:
%   Events in EEGLAB structure format
%
% You need Matlab R2020b or later AND the Signal processing toolbox installed
% to use this function.
%
% References for Matlab's edfRead function:
% [1] Kemp, Bob, Alpo Värri, Agostinho C. Rosa, Kim D. Nielsen, and John Gade. “A Simple Format for Exchange of Digitized Polygraphic Recordings.” Electroencephalography and Clinical Neurophysiology 82, no. 5 (May 1992): 391–93. https://doi.org/10.1016/0013-4694(92)90009-7.
% [2] Kemp, Bob, and Jesus Olivan. "European Data Format 'plus' (EDF+), an EDF Alike Standard Format for the Exchange of Physiological Data." Clinical Neurophysiology 114, no. 9 (2003): 1755–1761. https://doi.org/10.1016/S1388-2457(03)00123-8.
%
% More on EDF: https://www.edfplus.info/index.html
%
% Author: Cedric Cannard, April 2021
%
% Copyright (C) 2021 Cedric Cannard, ccannard@protonmail.com
%
% This program is free software; you can redistribute it and/or modify
% it under the terms of the GNU General Public License as published by
% the Free Software Foundation; either version 2 of the License, or
% (at your option) any later version.
%
% This program is distributed in the hope that it will be useful,
% but WITHOUT ANY WARRANTY; without even the implied warranty of
% MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
% GNU General Public License for more details.
%
% You should have received a copy of the GNU General Public License
% along with this program; if not, write to the Free Software
% Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

function EEG = import_EDF(inputname)

%Check for Matlab version and Signal processing toolbox
matlab_version = erase(version, ".");
matlab_version = str2double(matlab_version(1:3));
if matlab_version < 990 && ~license('test', 'Signal_Toolbox')
    errordlg('You need Matlab 2020b or later AND the Signal Processing Toolbox to use this function. You can try to download edfRead here: https://www.mathworks.com/matlabcentral/fileexchange/31900-edfread; or use EEGLAB''s Biosig toolbox');
    return
else
    disp('Matlab version > 2020a and Signal processing toolbox succesfully detected: importing EDF+ data...');
    
    if ~exist('ALLEEG','var'), eeglab; end
    EEG = eeg_emptyset;
    
    %Get filename and path
    if nargin == 0
        [fileName, filePath] = uigetfile2({ '*.edf' }, 'Select .EDF file');
        filePath = fullfile(filePath, fileName);
    else
        filePath = inputname;
    end
    
    %Import EDF data and annotations
    % edfData = edfread(filePath);
    [edfData, annot] = edfread(filePath, 'TimeOutputType', 'datetime' );
    info = edfinfo(filePath);
    annot = timetable2table(annot,'ConvertRowTimes',true);
    
    %Timestamps
    edfTime = timetable2table(edfData,'ConvertRowTimes',true);
    edfTime = datetime(table2array(edfTime(:,1)), 'Format', 'HH:mm:ss:SS');
    varTime = diff(edfTime);     %variability across samples
    
    %Sampling rate and timestamps
    sPerCell = mode(seconds(varTime));
    if sPerCell == 1
        sRate = info.NumSamples(1);
    else
        sRate = info.NumSamples(1)/sPerCell;
        %         startTime = edfTime(1);
        correctSize = length(edfTime)*sPerCell;
        %         correctTimes = zeros(correctSize,1);
        correctTimes(1) = edfTime(1);
        for i = 2:correctSize
            correctTimes(i,:) = correctTimes(i-1)+seconds(1);
        end
    end
    
    %Check sample rate stability
    nSrate = 1./seconds(unique(varTime));
    nSrate(isinf(nSrate)) = [];
    if (max(nSrate)-min(nSrate))/max(nSrate) > 0.01
        warning('Sampling rate varies: Data is either discontinuous (TAKEN CARE OF) or something is wrong with your sample rate (NOT TAKEN CARE OF)');
        
        %Boundaries
        index(2:length(varTime)+1,:) = varTime ~= mode(varTime);
        bound = find(index);
        
        %Gap durations
        for iGap = 1:length(bound)
            gaps(iGap) = edfTime(bound(iGap)) - edfTime(bound(iGap)-1);
        end
        
        %Segments
        seg(1,1) = edfTime(1);
        seg(1,2) = edfTime(bound(1)-1);
        count = 2;
        for iSeg = 1:length(bound)
            seg(count,1) = edfTime(bound(iSeg));
            if iSeg ~= length(bound)
                seg(count,2) = edfTime(bound(iSeg+1)-1);
            else
                seg(count,2) = edfTime(end);
            end
            count = count+1;
        end
        
        %Find segments for each event
        for iEv = 1:size(annot,1)
            ev(iEv,:).type = table2array(annot(iEv,2));
            ev(iEv,:).lat = datetime(table2array(annot(iEv,1)), 'Format', 'HH:mm:ss:SSS');
            for iSeg = 1:length(seg)
                if isbetween(ev(iEv,:).lat, seg(iSeg,1), seg(iSeg,2))
                    ev(iEv,:).seg = iSeg;
                end
            end
        end
        
        %Remove gaps to correct event latencies
        for iEv = 1:length(ev)
            if ev(iEv).seg > 1          %for segments after 1st gap
                gap = sum(gaps(1:ev(iEv).seg - 1));
                ev(iEv,:).removed_gap = gap;
                ev(iEv,:).correct_lat = ev(iEv,:).lat - gap;
            elseif ev(iEv,:).seg == 1   %segment before 1st gap
                ev(iEv,:).correct_lat = ev(iEv,:).lat;
            end
        end
        
        %         %add boundaries between segments so that EEGLAB filters can correct DC offset changes automatically
        %         indx = 1;
        %         for iEv = 0:length(ev)
        %             iEv = iEv+indx;
        %             if iEv < length(ev)
        %                 if ev(iEv).seg ~= ev(iEv+1).seg
        %                     EEG.event(indx,:).latency = round((latency*24*60*60*sRate)+1);   %add boundary at last event + 1 sample
        %                     EEG.event(indx,:).type = 'boundary';
        %                     EEG.event(indx,:).urevent = iEv;
        %                     indx = indx + 1;
        %                 end
        %             end
        %         end
        
        %Get event latencies adjusted to time 0 and in ms
        for iEv = 1:length(ev)
            latency = datenum(ev(iEv).correct_lat) - datenum(datetime(edfTime(1), 'Format', 'HH:mm:ss:SSS'));
            EEG.event(iEv,:).latency = round(latency*24*60*60*sRate);   %latency in ms
            EEG.event(iEv,:).type = char(ev(iEv).type);
            EEG.event(iEv,:).urevent = iEv;
        end
        EEG = eeg_checkset(EEG);
        
        %         %EEG data
        %         sRate = info.NumSamples(1);
        %         edfData = table2array(edfData)';
        %         eegData = [];
        %         for iChan = 1:size(edfData,1)
        %             sample = 1;
        %             for iCell = 1:size(edfData,2)
        %                 eegData(iChan, sample:sample+sRate-1) = single(edfData{iChan,iCell});
        %                 sample = sample + length(edfData{iChan,iCell});
        %             end
        %         end
        %
        %         %EEGLAB structure
        %         EEG.data = eegData;
        %         EEG.srate = sRate;
        %         %         EEG.srate = size(edfData{1,1},1)/seconds(mode(varTime)); %Get the correct sampling rate
        %         EEG.nbchan = size(EEG.data,1);
        %         EEG.pnts   = size(EEG.data,2);
        %         EEG.xmin = 0;
        %         EEG.trials = 1;
        %         EEG.format = char(info.Reserved);
        %         EEG.recording = char(info.Recording);
        %         EEG.unit = char(info.PhysicalDimensions);
        %         EEG = eeg_checkset(EEG);
        %
        %
        %         %Channel labels
        %         chanLabels = erase(upper(info.SignalLabels ),".");
        %         if ~ischar(chanLabels)
        %             for iChan = 1:length(chanLabels)
        %                 EEG.chanlocs(iChan).labels = char(chanLabels(iChan));
        %             end
        %         end
        %         EEG = eeg_checkset(EEG);
        
    else
        disp('Continuous data detected.');
        
        %Events
        for iEv = 1:size(annot,1)
            EEG.event(iEv,:).type = char(table2array(annot(iEv,2)));
            latency = datenum(datetime(table2array(annot(iEv,1)), 'Format', 'HH:mm:ss:SSS'));
            latency = latency - datenum(datetime(edfTime(1), 'Format', 'HH:mm:ss:SSS'));
            EEG.event(iEv,:).latency = round(latency*24*60*60*sRate);   %correct latency in ms
            EEG.event(iEv,:).urevent = iEv;
        end
        EEG = eeg_checkset(EEG);
        
    end
    
    %EEG data
    edfData = table2array(edfData)';
    eegData = [];
    for iChan = 1:size(edfData,1)
        sample = 1;
        for iCell = 1:size(edfData,2)
            cellData = edfData{iChan,iCell};
            if sPerCell == 1     %data with correct sample rate at import
                eegData(iChan, sample:sample+sRate-1) = cellData;
                %                 sample = sample + length(edfData{iChan,iCell});
                sample = sample + sRate;
            else  %for data with incorrect sample rate at import (e.g. RKS05 test file)
                for iSec = 1:sPerCell
                    eegData(iChan, sample:sample+sRate-1) = cellData(iSec:iSec+sRate-1);
                    sample = sample + sRate;
                end
            end
        end
    end
    
    %EEGLAB structure
    if exist('fileName','var'), 
        EEG.setname = fileName(1:end-4);
    else
        EEG.setname = 'EEG data';
    end        
    EEG.srate = sRate;
    EEG.data = eegData;
    EEG.nbchan = size(EEG.data,1);
    EEG.pnts   = size(EEG.data,2);
    EEG.xmin = 0;
    EEG.trials = 1;
    EEG.format = char(info.Reserved);
    EEG.recording = char(info.Recording);
    EEG.unit = char(info.PhysicalDimensions);
    EEG = eeg_checkset(EEG);
    
    %Channel labels
    chanLabels = erase(upper(info.SignalLabels ),".");
    if ~ischar(chanLabels)
        for iChan = 1:length(chanLabels)
            EEG.chanlocs(iChan).labels = char(chanLabels(iChan));
        end
    end
    EEG = eeg_checkset(EEG);
    
    EEG.data = bsxfun(@minus, eegData, mean(EEG.data,2));
    pop_eegplot(EEG,1,1,1);
        
end
end


