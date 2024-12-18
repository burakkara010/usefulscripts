#!/bin/bash
echo -e "\033[1;32m"
echo "script: export-folder-file-last-modified-v3.sh"
echo -e "\033[0m"
echo -e "\033[1;33m"
echo "This script will create an Excel file with the last modified date of all files in the current directory."
echo -e "\033[0m"

# Vraag of individuele mappen sheets moeten worden aangemaakt
read -p "The first sheet of the Excel file will contain all folders and files, but you also can split the folders into seperate sheets.
Do you want to create individual sheets per folder? (y/n): " create_individual_sheets
echo ""

echo "Starting: Please Be Patient, this can take some time for huge folder structures"


# Genereer een timestamp in het formaat: uur-minuut-dag-maand-jaar
timestamp=$(date +"%d%m-%Y-%H%M")

# Output Excel-bestand met timestamp
output_excel="$HOME/Downloads/export-folder-file-last-modified-${timestamp}.xlsx"

# Vereist: Python met xlsxwriter en tqdm
if ! python3 -c "import xlsxwriter" &>/dev/null; then
    echo "Python 'xlsxwriter' module not found. Install with: pip3 install xlsxwriter"
    exit 1
fi

if ! python3 -c "import tqdm" &>/dev/null; then
    echo "Python 'tqdm' module not found. Installeer with: pip3 install tqdm"
    exit 1
fi

# Maak een Python-script dat Excel genereert
cat <<EOF > /tmp/export-folder-file-last-modified.py
import os
import xlsxwriter
import subprocess
from tqdm import tqdm  # for the progress bar

# Output file
output_file = os.path.expanduser("${output_excel}")

# Create an Excel workbook
workbook = xlsxwriter.Workbook(output_file)

# Create a general sheet for all folders and files
worksheet_all = workbook.add_worksheet("All Folders & Files")
worksheet_all.write(0, 0, "Folder")
worksheet_all.write(0, 1, "Filename")
worksheet_all.write(0, 2, "Last Modified Date")

# Get folders in the current directory
folders = [d for d in os.listdir() if os.path.isdir(d)]

# Add files from all folders to the "All Folders & Files" sheet
row_all = 1
for folder in tqdm(folders, desc="Processing folders", unit="folder"):
    # Haal bestanden gesorteerd op 'last modified date'
    result = subprocess.run(f"ls -lt '{folder}'", shell=True, capture_output=True, text=True)
    files = result.stdout.strip().split("\n")[1:]  # First line (total) is skipped
    
    for file_line in files:
        parts = file_line.split()
        if len(parts) >= 9:
            last_modified = f"{parts[5]} {parts[6]} {parts[7]}"  # Date
            filename = " ".join(parts[8:])  # Filename
            worksheet_all.write(row_all, 0, folder)
            worksheet_all.write(row_all, 1, filename)
            worksheet_all.write(row_all, 2, last_modified)
            row_all += 1

# Ask if individual folder sheets should be created
create_individual_sheets = os.environ.get("CREATE_INDIVIDUAL_SHEETS", "n").lower() in ["y", "yes"]

if create_individual_sheets:
    # Make individual sheets for each folder
    for folder in tqdm(folders, desc="Processing individual folders", unit="folder"):
        worksheet = workbook.add_worksheet(folder[:31])  # Max 31 characters for sheet names
        worksheet.write(0, 0, "Filename")
        worksheet.write(0, 1, "Last Modified Date")

        # Get files sorted by 'last modified date'
        result = subprocess.run(f"ls -lt '{folder}'", shell=True, capture_output=True, text=True)
        files = result.stdout.strip().split("\n")[1:]  # Eerste regel (total) overslaan
        
        # Make a progress bar for the folders
        for row, file_line in enumerate(tqdm(files, desc=f"Processing files in {folder}", unit="file", leave=False)):
            parts = file_line.split()
            if len(parts) >= 9:
                last_modified = f"{parts[5]} {parts[6]} {parts[7]}"  # Date
                filename = " ".join(parts[8:])  # Filename
                worksheet.write(row + 1, 0, filename)
                worksheet.write(row + 1, 1, last_modified)

# Save the Excel file
workbook.close()
print(f"Excel-File Created: {output_file}")
EOF

# Choice to create individual sheets
if [[ "$create_individual_sheets" =~ ^[yY](es)?$ ]]; then
    export CREATE_INDIVIDUAL_SHEETS="y"
else
    export CREATE_INDIVIDUAL_SHEETS="n"
fi

# Run the Python script
python3 /tmp/export-folder-file-last-modified.py
