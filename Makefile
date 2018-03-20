all: fix
	cp -fr inventor/CAM/* /Volumes/ClayStick/Turn\ Touch\ CAM/
	diskutil unmount /Volumes/ClayStick

clean:
	rm -fr /Volumes/ClayStick/Turn\ Touch\ CAM/*

fix:
	python inventor/CAM/fix.py
	