#!/usr/bin/env python
import os
import glob

def delete_matching_lines(pattern):
    directory = os.path.dirname(os.path.realpath(__file__))
    for file in glob.glob(os.path.join(directory, "*.sbp")):
        f = open(file)
        filelines = f.read().splitlines()
        output = []
        found = 0
        # Preserve the last 'C7'/pattern
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
        if found:
            print " ---> Rewriting %-48s found %s C7s" % (os.path.basename(file), found)
        

def merge_files(top_prefix, bottom_prefix, combined_filename):
    directory = os.path.dirname(os.path.realpath(__file__))
    top_filename = None
    top_file = None
    bottom_filename = None
    bottom_file = None
    merged_file = []
    f = open(os.path.join(directory, combined_filename), 'r')
    original_merged_file = f.read()
    
    for file in glob.glob(os.path.join(directory, "*.sbp")):
        if top_prefix in file:
            top_filename = os.path.basename(file)
            f = open(file)
            top_file = f.read().splitlines()
        if bottom_prefix in file:
            bottom_filename = os.path.basename(file)
            f = open(file)
            bottom_file = f.read().splitlines()

    for l, line in enumerate(top_file):
        if line == 'C7' or line == 'JH': continue
        merged_file.append(line + '\r\n')
        
    found_c6 = False
    for l, line in enumerate(bottom_file):
        if found_c6:
            merged_file.append(line + '\r\n')
        if line == 'C6':
            found_c6 = True
            merged_file.append("\r\n' Start of %s\r\n" % bottom_prefix)
    f.close()
    f = open(os.path.join(directory, combined_filename), 'w')
    f.writelines(merged_file)
    f.close()
    
    if ''.join(merged_file) != original_merged_file:
        print """
     ---> Merging %s lines from %s 
                  %s lines from %s
               -> %s lines in %s""" % (len(top_file), top_filename, len(bottom_file), bottom_filename, len(merged_file), combined_filename)
    

def speed_adjustment(wood, speed, min_speed=0.5):
    directory = os.path.dirname(os.path.realpath(__file__))
    for cam_file in glob.glob(os.path.join(directory, "*.sbp")):
        f = open(cam_file)
        filelines = f.read().splitlines()
        output = []
        for l, line in enumerate(filelines):
            if line.startswith('VS'):
                parts = line.split(',')
                old_plunge_speed = float(parts.pop())
                old_feed_speed = float(parts.pop())
                new_feed_speed = round(old_feed_speed * speed, 1)
                new_plunge_speed = round(old_plunge_speed * speed, 1)
                
                if old_feed_speed < min_speed:
                    new_feed_speed = old_feed_speed
                    new_plunge_speed = old_plunge_speed
                    
                print " ---> %s: %-48s shifting %s,%s to %s,%s" % (wood, os.path.basename(cam_file), 
                    old_feed_speed, old_plunge_speed, new_feed_speed, new_plunge_speed)
                output.append("%s, %s, %s\r\n" % (', '.join(parts), new_feed_speed, new_plunge_speed))
            else:
                output.append(line + '\r\n')
        f.close()
        
        f = open(os.path.join(os.path.dirname(os.path.realpath(__file__)), os.path.join(wood, os.path.basename(cam_file))), 'w+')
        f.writelines(output)
        f.close()
    

if __name__ == "__main__":
    delete_matching_lines('C7')
    speed_adjustment('rosewood', 0.333)
    # merge_files('1001', '2001', '0001 All Cavity Flat.sbp')
    # merge_files('1002', '2002', '0002 All Cavity Ball.sbp')
    # merge_files('1011', '2011', '0011 All Core Ball.sbp')