all: fix
	cp -fr inventor/CAM/* /Volumes/ClayStick/enclosure/inventor/CAM/
	diskutil unmount /Volumes/ClayStick

clean:
	rm -fr /Volumes/ClayStick/enclosure/inventor/CAM/*         

fix:
	python inventor/CAM/fix.py
	