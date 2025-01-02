import pandas as pd
import numpy as np
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
    'Time_to_First_Token-TTFT_Avg',
    'Time_to_First_Token-TTFT_P50',
    'Time_to_First_Token-TTFT_P90',
    'Time_to_First_Token-TTFT_P99',
    'Time_Per_Output_Token-TPOT_Avg',
    'Time_Per_Output_Token-TPOT_P50',
    'Time_Per_Output_Token-TPOT_P90',
    'Time_Per_Output_Token-TPOT_P99',
    'Output_Tokens_per_Second',
    'Input_Tokens_per_Second',
    'Onput_Tokens',
    'Input_Tokens'
]

df = pd.read_csv(csv_file, delimiter=',')
existing_columns_to_average = [col for col in columns_to_average if col in df.columns]
columns_to_keep = ['No', 'run_name'] + existing_columns_to_average

df_filtered = df[columns_to_keep]
average_values = df_filtered[existing_columns_to_average].mean()
rounded_values = {col: np.ceil(avg * 100) / 100 for col, avg in zip(existing_columns_to_average, average_values)}

# Create a new row to append to the DataFrame
new_row = {col: rounded_values[col] for col in existing_columns_to_average}
new_row['run_name'] = 'Average'
new_row_df = pd.DataFrame([new_row])
df_filtered = pd.concat([df_filtered, new_row_df], ignore_index=True)

# Save the new data
df_filtered.to_csv(csv_file, index=False, sep=',')
print(f"CSV file {csv_file} has been updated.")
