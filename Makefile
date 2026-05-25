.PHONY: run test

run:
	nvim -c "set rtp+=$(PWD)" -c "source plugin/strudel.lua"

test:
	nvim --headless --noplugin -u tests/minimal_init.lua \
		-c "PlenaryBustedDirectory tests/ { minimal_init = 'tests/minimal_init.lua' }" \
		-c "qall!"
