#!/bin/bash
echo -e "\033[1;32m"
echo "script: export-folder-file-last-modified-v1.2.sh"
echo -e "\033[0m"
echo -e "\033[1;33m"
echo "This script will create an Excel file with the last modified date and file sizes of all files in the current directory, including nested folders."
echo -e "\033[0m"

########### Vraag of individuele mappen sheets moeten worden aangemaakt
read -p "The first sheet of the Excel file will contain all folders and files, but you also can split the folders into separate sheets.
Do you want to create individual sheets per folder? (y/n): " create_individual_sheets
echo ""

echo "Starting: Please Be Patient, the script will dynamically scan and process files per folder."
echo ""

########### Genereer een timestamp in het formaat: uur-minuut-dag-maand-jaar
timestamp=$(date +"%d%m-%Y-%H%M")

########### Output Excel-bestand met timestamp
output_excel="$HOME/Downloads/export-folder-file-last-modified-${timestamp}.xlsx"

########### Vereist: Python met xlsxwriter en tqdm
if ! python3 -c "import xlsxwriter" &>/dev/null; then
    echo "Python 'xlsxwriter' module not found. Install with: pip3 install xlsxwriter"
    exit 1
fi

if ! python3 -c "import tqdm" &>/dev/null; then
    echo "Python 'tqdm' module not found. Install with: pip3 install tqdm"
    exit 1
fi

########### Maak een Python-script dat Excel genereert
cat <<EOF > /tmp/export-folder-file-last-modified.py
import os
import time
import xlsxwriter
from tqdm import tqdm  # for the progress bar

# Function to format file size dynamically
def format_file_size(size_in_bytes):
    if size_in_bytes < 1024:
        return f"{size_in_bytes} B"
    elif size_in_bytes < 1024**2:
        return f"{size_in_bytes / 1024:.2f} KB"
    elif size_in_bytes < 1024**3:
        return f"{size_in_bytes / 1024**2:.2f} MB"
    else:
        return f"{size_in_bytes / 1024**3:.2f} GB"

# Output file
output_file = os.path.expanduser("${output_excel}")

# Create an Excel workbook
workbook = xlsxwriter.Workbook(output_file)

# Create a general sheet for all folders and files
worksheet_all = workbook.add_worksheet("All Folders & Files")
worksheet_all.write(0, 0, "Folder")
worksheet_all.write(0, 1, "Filename")
worksheet_all.write(0, 2, "File Size")
worksheet_all.write(0, 3, "Last Modified Date")

# Ask if individual folder sheets should be created
create_individual_sheets = os.environ.get("CREATE_INDIVIDUAL_SHEETS", "n").lower() in ["y", "yes"]

row_all = 1  # Track rows for the "All Folders & Files" sheet

# Process each folder dynamically
for root, dirs, files in os.walk("."):
    folder = os.path.relpath(root, start=".")  # Relatief pad naar huidige folder
    print(f"\nProcessing folder: {folder}")
    if files:
        progress_bar = tqdm(files, desc=f"Processing {folder}", unit="file")
        for file in progress_bar:
            filepath = os.path.join(root, file)
            try:
                last_modified = os.path.getmtime(filepath)
                last_modified_date = time.strftime('%Y-%m-%d %H:%M:%S', time.localtime(last_modified))
                file_size = os.path.getsize(filepath)
                formatted_size = format_file_size(file_size)
            except Exception as e:
                last_modified_date = "Error"
                formatted_size = "Error"

            # Add to the general sheet
            worksheet_all.write(row_all, 0, folder)
            worksheet_all.write(row_all, 1, file)
            worksheet_all.write(row_all, 2, formatted_size)
            worksheet_all.write(row_all, 3, last_modified_date)
            row_all += 1
        progress_bar.close()

        # Add individual sheet if enabled
        if create_individual_sheets:
            worksheet = workbook.add_worksheet(folder[:31])  # Max 31 characters for sheet names
            worksheet.write(0, 0, "Filename")
            worksheet.write(0, 1, "File Size")
            worksheet.write(0, 2, "Last Modified Date")

            for row, file in enumerate(files, start=1):
                filepath = os.path.join(root, file)
                try:
                    last_modified = os.path.getmtime(filepath)
                    last_modified_date = time.strftime('%Y-%m-%d %H:%M:%S', time.localtime(last_modified))
                    file_size = os.path.getsize(filepath)
                    formatted_size = format_file_size(file_size)
                except Exception as e:
                    last_modified_date = "Error"
                    formatted_size = "Error"

                worksheet.write(row, 0, file)
                worksheet.write(row, 1, formatted_size)
                worksheet.write(row, 2, last_modified_date)

# Save the Excel file
workbook.close()
print(f"\nExcel file created: {output_file}")
EOF

########### Choice to create individual sheets
if [[ "$create_individual_sheets" =~ ^[yY](es)?$ ]]; then
    export CREATE_INDIVIDUAL_SHEETS="y"
else
    export CREATE_INDIVIDUAL_SHEETS="n"
fi

########### Run the Python script
python3 /tmp/export-folder-file-last-modified.py
