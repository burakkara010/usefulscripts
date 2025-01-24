#!/bin/bash
echo -e "\033[1;32m"
echo "script: export-folder-file-last-modified-v4.sh"
echo -e "\033[0m"
echo -e "\033[1;33m"
echo "This script will create an Excel file with the last modified date and file sizes of all files in the current directory, including nested folders."
echo -e "\033[0m"

########### Vraag of individuele mappen sheets moeten worden aangemaakt
read -p "The first sheet of the Excel file will contain all folders and files, but you also can split the folders into separate sheets.
Do you want to create individual sheets per folder? (y/n): " create_individual_sheets
echo ""

echo "Starting: Please Be Patient, this can take some time for huge folder structures"
echo "especially when scanning cloud fileshares or if individual sheets are created."



########### Animatie: Scanning folders and files ...
function animate_dots() {
    local dots=0
    local max_dots=4
    while :; do
        dots=$(( (dots + 1) % (max_dots + 1) ))
        echo -ne "\rScanning folders and files $(printf '.%.0s' $(seq 1 $dots))   " # Puntjes oplichten
        sleep 0.5
    done
}

########### Start de animatie in een achtergrondproces
animate_dots &
anim_pid=$!  # Sla het proces-ID op

########### Tijdelijke simulatie van werk (vervang dit met je echte logica)
sleep 3  # Tijdelijk wachten om de animatie te testen

########### Stop de animatie zodra het werk klaar is
kill "$anim_pid" &>/dev/null
wait "$anim_pid" 2>/dev/null

echo -ne "\rScanning complete!                          \n" 



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

# Count total files for progress bar
total_files = sum([len(files) for _, _, files in os.walk(".")])

# Create an Excel workbook
workbook = xlsxwriter.Workbook(output_file)

# Create a general sheet for all folders and files
worksheet_all = workbook.add_worksheet("All Folders & Files")
worksheet_all.write(0, 0, "Folder")
worksheet_all.write(0, 1, "Filename")
worksheet_all.write(0, 2, "File Size")
worksheet_all.write(0, 3, "Last Modified Date")

# Add files from all folders, including nested folders, to the "All Folders & Files" sheet
row_all = 1
progress_bar = tqdm(total=total_files, desc="Processing files", unit="file")
for root, dirs, files in os.walk("."):
    folder = os.path.relpath(root, start=".")  # Relatief pad naar huidige folder
    for file in files:
        filepath = os.path.join(root, file)
        last_modified = os.path.getmtime(filepath)
        last_modified_date = time.strftime('%Y-%m-%d %H:%M:%S', time.localtime(last_modified))
        file_size = os.path.getsize(filepath)
        formatted_size = format_file_size(file_size)
        worksheet_all.write(row_all, 0, folder)
        worksheet_all.write(row_all, 1, file)
        worksheet_all.write(row_all, 2, formatted_size)
        worksheet_all.write(row_all, 3, last_modified_date)
        row_all += 1
        progress_bar.update(1)  # Update progress bar for each file
progress_bar.close()

# Ask if individual folder sheets should be created
create_individual_sheets = os.environ.get("CREATE_INDIVIDUAL_SHEETS", "n").lower() in ["y", "yes"]

if create_individual_sheets:
    # Make individual sheets for each folder
    for root, dirs, files in tqdm(os.walk("."), desc="Processing individual folders", unit="folder"):
        folder = os.path.relpath(root, start=".")
        if not files:  # Sla over als er geen bestanden in de map zijn
            continue
        worksheet = workbook.add_worksheet(folder[:31])  # Max 31 tekens voor sheet-namen
        worksheet.write(0, 0, "Filename")
        worksheet.write(0, 1, "File Size")
        worksheet.write(0, 2, "Last Modified Date")

        for row, file in enumerate(files, start=1):
            filepath = os.path.join(root, file)
            last_modified = os.path.getmtime(filepath)
            last_modified_date = time.strftime('%Y-%m-%d %H:%M:%S', time.localtime(last_modified))
            file_size = os.path.getsize(filepath)
            formatted_size = format_file_size(file_size)
            worksheet.write(row, 0, file)
            worksheet.write(row, 1, formatted_size)
            worksheet.write(row, 2, last_modified_date)

# Save the Excel file
workbook.close()
print(f"Excel-File Created: {output_file}")
EOF

########### Choice to create individual sheets
if [[ "$create_individual_sheets" =~ ^[yY](es)?$ ]]; then
    export CREATE_INDIVIDUAL_SHEETS="y"
else
    export CREATE_INDIVIDUAL_SHEETS="n"
fi

########### Run the Python script
python3 /tmp/export-folder-file-last-modified.py
