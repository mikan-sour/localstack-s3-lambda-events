import { S3, } from 'aws-sdk';
import { Context, S3Event } from 'aws-lambda';
import * as dotenv from 'dotenv'
dotenv.config()

const s3 = new S3({
    apiVersion: '2006-03-01',
    endpoint: `${process.env.AWS_ENDPOINT}`,
    s3ForcePathStyle: true,
});

export async function handler(event: S3Event, _: Context) {
    const bucket = event.Records[0].s3.bucket.name;
    const key = decodeURIComponent(event.Records[0].s3.object.key.replace(/\+/g, ' '));
    try {
        const copyParams:S3.CopyObjectRequest = {
            Bucket: `${process.env.AWS_S3_BUCKET_TWO}`,
            CopySource: `/${process.env.AWS_S3_BUCKET_ONE}/${key}`,
            Key: key
        };
        
        await s3.copyObject(copyParams, (err, data) => {
            if (err) console.log(err, err.stack); // an error occurred
            else console.log(data);           // successful response
        }).promise();

    } catch (err) {
        console.log(err);
        const message = `Error getting object ${key} from bucket ${bucket}. Make sure they exist and your bucket is in the same region as this function.`;
        console.log(message);
        throw new Error(message);
    }
}