all: fix
	cp -fr inventor/CAM/* /Volumes/ClayStick/CAM/
	diskutil unmount /Volumes/ClayStick

clean:
	rm -fr /Volumes/ClayStick/CAM/*

fix:
	python inventor/CAM/fix.py
	