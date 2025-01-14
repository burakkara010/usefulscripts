import requests
import time
import os
from datetime import datetime

appname = "WebVisitScheduler"
version = "v1.0"

# ANSI escape codes voor kleur
GREEN = "\033[32m"
RED = "\033[31m"
RESET = "\033[0m"

print(f"\n")
print(f"{GREEN} ><><><><><><><><><><><><><><><><><><><><><><{RESET}")
print(f"{GREEN}   Thanks for using {appname} {version}  {RESET}")
print(f"{GREEN} ><><><><><><><><><><><><><><><><><><><><><><{RESET}")
print(f"Author: Burak Kara")
print(f"\n")

# Date Variables
month_number = datetime.now().month  # Month number
year = datetime.now().year # Year

# Script Variables
URL = input("Please enter the URL of the website \n(including http:// or https://): ")
AMOUNT_VISITS = 5  # Amount of times to visit the website per cycle
INTERVAL_CYCLES = 5  # Interval between cycles in minutes
TIME_SLEEP = 10  # Pause between individual visits in seconds
LOG_LOCATION = os.path.expanduser(f"~/Downloads/WebVisitScheduler/{URL}/{year}-Month-{month_number}-WebVisitScheduler-output.txt") # Log file path



def get_logfile_name():
    """Generate the log file name based on the current year and month."""  
    log_path = LOG_LOCATION
    return log_path

def log(message):
    """Log a message with a timestamp to the file.""" 
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    logfile_name = get_logfile_name()
    
    # Check if the directory exists, if not create it
    os.makedirs(os.path.dirname(logfile_name), exist_ok=True)
    
    # Check if the log file exists, if not create it
    if not os.path.exists(logfile_name):
        with open(logfile_name, "w") as logfile:
            logfile.write(f"Logfile created on {timestamp}\n")  # Add a header to the log file
    
    # Add the log message to the log file
    with open(logfile_name, "a") as logfile:
        logfile.write(f"[{timestamp}] {message}\n")
    
    # Print to console
    print(f"[{timestamp}] {message}")

def countdown_timer(time_in_seconds, message):
    """Shows a countdown timer in the same log line.""" 
    for remaining in range(time_in_seconds, 0, -1):
        print(f"\r{message} Wait for {remaining} seconds...", end="")
        time.sleep(1)
    print(f"\r{message} Next step starts now..!              ")  # Clears the line

def visit_website(url, amount_visits):
    for i in range(amount_visits):
        try:
            response = requests.get(url, timeout=10)
            if response.status_code == 200:
                log(f"{GREEN}Visit {i+1}: {URL} Successful visited !!{RESET}")
            else:
                log(f"{RED}Visit {i+1}: Problem with website. Statuscode: {response.status_code}{RESET}")
        except requests.exceptions.RequestException as e:
            log(f"{RED}Visit {i+1}: Problem with connecting: {e}{RESET}")

        # Countdown for the next visit
        countdown_timer(TIME_SLEEP, "[Cooldown for next visit]")  # Countdown for the next visit

def countdown_timer_cycle(time_in_seconds):
    """Shows a countdown between cycles."""
    countdown_timer(time_in_seconds, "[Countdown]")  # Countdown for next cycle

def main():
    while True:
        log("New Cycle started...")
        log(f"Cycle for website: {URL}")
        visit_website(URL, AMOUNT_VISITS)
        countdown_timer_cycle(INTERVAL_CYCLES * 60)  # Countdown voor de wachttijd van 1 minuut

if __name__ == "__main__":
    main()
