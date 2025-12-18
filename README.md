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

