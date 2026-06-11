#!/usr/bin/python3

import pickle
import sys
from pprint import pprint
import json

with open(sys.argv[1], "rb") as f:
    data = pickle.load(f)

print(json.dumps(data, indent=2))
