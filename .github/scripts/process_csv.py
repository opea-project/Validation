import pandas as pd
import argparse

# Set up command line argument parsing
parser = argparse.ArgumentParser(description="Process a CSV file and calculate column averages.")
parser.add_argument('csv_file', type=str, help='The path to the input CSV file.')
args = parser.parse_args()

csv_file = args.csv_file

columns_to_average = [
    'Average_token_latency',
    'Duration',
    'End_to_End_latency_Avg',
    'End_to_End_latency_P50',
    'End_to_End_latency_P90',
    'End_to_End_latency_P99',
    'First_token_latency_Avg',
    'First_token_latency_P50',
    'First_token_latency_P90',
    'First_token_latency_P99',
    'Next_token_latency_Avg',
    'Next_token_latency_P50',
    'Next_token_latency_P90',
    'Next_token_latency_P99',
    'Output_Tokens_per_Second'
]
columns_to_keep = ['No', 'run_name'] + columns_to_average

df = pd.read_csv(csv_file, delimiter=',')

df_filtered = df[columns_to_keep]
average_values = df_filtered[columns_to_average].mean()

# Create a new row to append to the DataFrame
new_row = {col: avg for col, avg in zip(columns_to_average, average_values)}
new_row['run_name'] = 'Average'
new_row_df = pd.DataFrame([new_row])
df_filtered = pd.concat([df_filtered, new_row_df], ignore_index=True)

# Save the new data
df_filtered.to_csv(csv_file, index=False, sep=',')
print(f"CSV file {csv_file} has been updated.")
