all: fix
	cp -fr inventor/CAM/* /Volumes/ClayStick/enclosure/inventor/CAM/
	diskutil unmount /Volumes/ClayStick
	
fix:
	python inventor/CAM/fix.py
	