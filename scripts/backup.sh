#!/bin/bash
cd /home/ubuntu/tdex-box/tdexd/db/ && sudo /usr/bin/aws s3 sync . s3://tdexdb-terraform-test/db/