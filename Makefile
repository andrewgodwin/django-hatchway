.PHONY: test release

test:
	pytest

release:
	python3 -m build
	python3 -m twine upload dist/*
