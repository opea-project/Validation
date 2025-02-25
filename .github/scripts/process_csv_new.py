import pandas as pd
import numpy as np
import argparse

# Set up command line argument parsing
parser = argparse.ArgumentParser(description="Process a CSV file and calculate column averages.")
parser.add_argument('csv_file', type=str, help='The path to the input CSV file.')
args = parser.parse_args()

csv_file = args.csv_file

columns_to_keep = [
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
    'Input_Tokens',
    'Average_token_latency',
    'Duration',
]

df = pd.read_csv(csv_file, delimiter=',')
df = df[columns_to_keep]
df.to_csv(csv_file, index=False)
