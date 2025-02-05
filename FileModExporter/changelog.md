# Changelog

## [v1.3.0-beta] 
2025-01-29
<br />

**Optimization:**
<br />
The script was gathering the entire folder structure before starting with the actual export. Now the script is starting directly from the first folder in alphabetic order and proceeds exporting. This starts the export immediately instead of waiting for huge file sctructure scan which can take a lot of time. 

___

## [v1.2.0] 
2025-01-24
<br />
<br />
**Dynamic Progress Bar:**
<br />
Implemented a progress bar using tqdm to display real-time progress while processing files. The progress bar updates with each file and provides a smooth user experience.
Automatically counts the total number of files beforehand to calculate accurate progress.
<br />
<br />
**File Size Formatting:**
<br />
Added dynamic file size formatting for better readability:
Files < 1 KB: Displayed in bytes (B).
Files < 1 GB: Displayed in kilobytes (KB) or megabytes (MB).
Files < 1 TB: Displayed in gigabytes (GB).
<br />
<br />
**Individual Sheets Per Folder:**
<br />
Added functionality to create individual Excel sheets for each folder when the user selects y or yes at the prompt.
Individual sheets include Filename, File Size, and Last Modified Date columns.
<br />
<br />
**Environment Variable Support:**
<br />
Added support for the CREATE_INDIVIDUAL_SHEETS environment variable to manage the creation of individual folder sheets without user interaction.
<br />
___
<br />

## [v1.1.0] 
2025-01-14
<br />
**Added**
<br />
Progressbar which shows the total and elapsed time
