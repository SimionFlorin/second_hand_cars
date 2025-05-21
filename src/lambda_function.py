import json
import pandas as pd
import boto3
import os
from io import StringIO

# Define mandatory fields for model training
MANDATORY_FIELDS = {
    'CarName': 'string',  # Car model name
    'fueltype': 'string',  # Type of fuel
    'carbody': 'string',  # Body type
    'enginesize': 'numeric',  # Engine size
    'horsepower': 'numeric',  # Horsepower
    'wheelbase': 'numeric',  # Wheelbase
    'carlength': 'numeric',  # Car length
    'carwidth': 'numeric',  # Car width
    'curbweight': 'numeric',  # Curb weight
    'cylindernumber': 'numeric',  # Number of cylinders
    'Price': 'numeric'  # Target variable
}

def validate_mandatory_fields(df):
    """Validate that all mandatory fields are present and have correct data types."""
    missing_fields = []
    invalid_types = []
    
    for field, expected_type in MANDATORY_FIELDS.items():
        if field not in df.columns:
            missing_fields.append(field)
            continue
            
        if expected_type == 'numeric':
            if not pd.api.types.is_numeric_dtype(df[field]):
                invalid_types.append(f"{field} (expected numeric)")
        elif expected_type == 'string':
            if not pd.api.types.is_string_dtype(df[field]):
                invalid_types.append(f"{field} (expected string)")
    
    return missing_fields, invalid_types

def lambda_handler(event, context):
    # Initialize S3 client
    s3 = boto3.client('s3')
    
    # Get the source bucket and file key from the event
    source_bucket = event['Records'][0]['s3']['bucket']['name']
    file_key = event['Records'][0]['s3']['object']['key']
    
    try:
        # Read the CSV file from S3
        response = s3.get_object(Bucket=source_bucket, Key=file_key)
        df = pd.read_csv(response['Body'])
        
        # Validate mandatory fields
        missing_fields, invalid_types = validate_mandatory_fields(df)
        if missing_fields or invalid_types:
            error_message = {
                'statusCode': 400,
                'body': json.dumps({
                    'error': 'Invalid data format',
                    'missing_fields': missing_fields,
                    'invalid_types': invalid_types
                })
            }
            raise ValueError(json.dumps(error_message))
        
        # List of columns to drop (personal/irrelevant information)
        columns_to_drop = [
            'car_ID',  # Identifier not useful for prediction
            'ownername',  # Personal information
            'owneremail',  # Personal information
            'dealershipaddress',  # Location specific
            'saledate',  # Temporal information
            'iban'  # Financial information
        ]
        
        # Drop irrelevant columns
        df = df.drop(columns=[col for col in columns_to_drop if col in df.columns])
        
        # Remove rows with missing mandatory data
        df = df.dropna(subset=list(MANDATORY_FIELDS.keys()))
        
        # Handle imputable missing values
        # Numeric columns can be imputed with median
        numeric_columns = ['compressionratio', 'peakrpm', 'citympg', 'highwaympg']
        
        for col in numeric_columns:
            if col in df.columns:
                df[col] = df[col].fillna(df[col].median())
        
        # Categorical columns can be imputed with mode
        categorical_columns = ['aspiration', 'doornumber', 'drivewheel', 'enginelocation', 'color']
        
        for col in categorical_columns:
            if col in df.columns:
                df[col] = df[col].fillna(df[col].mode()[0])
        
        # Convert cylindernumber to numeric (remove '.0' if present)
        df['cylindernumber'] = df['cylindernumber'].replace('\.0$', '', regex=True)
        
        # Save processed file to curated zone
        curated_bucket = os.environ['CURATED_BUCKET']
        output_key = f"processed_{file_key}"
        
        # Convert DataFrame to CSV
        csv_buffer = StringIO()
        df.to_csv(csv_buffer, index=False)
        
        # Upload to curated zone
        s3.put_object(
            Bucket=curated_bucket,
            Key=output_key,
            Body=csv_buffer.getvalue()
        )
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'File processed successfully',
                'source_file': file_key,
                'destination_file': output_key,
                'rows_processed': len(df),
                'mandatory_fields_validated': list(MANDATORY_FIELDS.keys())
            })
        }
        
    except Exception as e:
        print(f"Error processing file {file_key}: {str(e)}")
        raise e 