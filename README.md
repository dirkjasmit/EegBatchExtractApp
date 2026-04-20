# EegBatchExtractApp

Extract EEG parameters from cleaned EEG files (or review data in a loop)

## Steps for running EegBatchExtractApp

### buttons and main screen settings
1. Use the 'Impute/Select' button to selcct an EEG file with a full EEG channel set. This removes unwanted (non-EEG) channels.
2. Select the checkbox if missing channels are to be imputed. There is a choice for channel signal interpolation or to impute the missing data statistically AFTER running the feature extraction.
3. Select the files to be analyzed.
4. Select he analysis to be performed (see below). For some analyses, also set the frequency to be analyzed.
5. select analysis/calculation options
6. run by pressing 'Batch'

The program will tell you where the data were stored. There will always be the global variable ResultTable with the filenames. Pathnames will have been removed.

### description of the analyses
DFA = detrended fluctutaion analysis: <requires filter selection> First filter in the freqency band then extract the decay exponent in long range temporal correlations (Linkenkaer-Hansen 2001).
IAF = Individual Alpha Frequency: prompts for a frequency window and determines the IAF
Coherence: Calculates coherence spectra and stroes in gloabl variable MeanCOH
Power: <requires filter selection> calculates power in the selected frequency band
PSD: Prompts for lower and upper frequency limits, and calculates power spectral desnity in microV^2/Hz with hanning windows of 4 sec epochs, data summed into 1 Hz bins.
FAA: frontal alpha asymmetry
ERP/ERSP: prompts for event codes / settings and calculates ERP/ERSP
Review: loops thru the files and opens a reviewing window. Saves the data as <path>/Rev_<filename>
MSE: multiscale entroy
Band cross PSD: PSD with cross-spectral desnities (across channels)
FOOOF: One-over-f parsing of the power spectrum plus up to 3 peaks on top.



