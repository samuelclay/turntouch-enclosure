#!/usr/bin/env python
import os
import glob

def deleteMatchingLines(pattern):
    directory = os.path.dirname(os.path.realpath(__file__))
    for file in glob.glob(os.path.join(directory, "*.sbp")):
        print " ---> Rewriting %s" % file 
        f = open(file)
        filelines = f.read().splitlines()
        output = []
        lastPatternIndex = (x for x in reversed([y for y in enumerate(filelines)]) if x[1] == pattern).next()[0]
        for l, line in enumerate(filelines):
            if not pattern in line or l == lastPatternIndex:
                output.append(line + '\r\n')
        f.close()
        f = open(file, 'w')
        f.writelines(output)
        f.close()

if __name__ == "__main__":
    deleteMatchingLines('C7')