#!/usr/bin/env python
import os
import glob

def deleteMatchingLines(pattern):
    directory = os.path.dirname(os.path.realpath(__file__))
    for file in glob.glob(os.path.join(directory, "*.sbp")):
        f = open(file)
        filelines = f.read().splitlines()
        output = []
        found = 0
        lastPatternIndex = (x for x in reversed([y for y in enumerate(filelines)]) if x[1] == pattern).next()[0]
        for l, line in enumerate(filelines):
            if not pattern in line or l == lastPatternIndex:
                output.append(line + '\r\n')
            else:
                found += 1
        f.close()
        f = open(file, 'w')
        f.writelines(output)
        f.close()
        print " ---> Rewriting %-32s found %s C7s" % (os.path.basename(file), found)
        

if __name__ == "__main__":
    deleteMatchingLines('C7')