.SUFFIXES: .erl .beam .yrl

.erl.beam:
				erlc -W $<

.yrl.erl:
				erlc -W $<

ERL = erl -boot start_clean

MODS = footrest

all: compile

compile: ${MODS:%=%.beam}

clean:
				rm -rf *.beam erl_crash.dump
