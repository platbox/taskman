APP_NAME = taskman

REBAR = $(shell which rebar 2>/dev/null || which ./rebar)
DIALYZER = dialyzer

CONFIG ?= dev.config
CONFIG_TESTS ?= $(shell ls tests.config 2>/dev/null || echo $(CONFIG))

.PHONY: all compile deps clean distclean test eunit

all: compile

deps: $(REBAR)
	$(REBAR) get-deps

compile: deps
	$(REBAR) compile

dc:
	$(REBAR) compile skip_deps=true

test: dc
	ERL_FLAGS="-config $(CONFIG_TESTS)" $(REBAR) eunit skip_deps=true

xref: dc
	$(REBAR) xref

clean: $(REBAR)
	$(REBAR) clean

distclean: clean
	$(REBAR) delete-deps
	rm -rfv plts

## dialyzer

ERL_LIBDIR = $(shell erl -noshell -noinput -eval 'io:format("~s~n", [code:lib_dir()]), halt().')
ERL_LIBAPPS = $(shell ls $(ERL_LIBDIR) | awk -F "-" '{print $$1}' | sed '/erl_interface/d;/jinterface/d;/odbc/d;/wx/d')

~/.dialyzer_plt:
	$(DIALYZER) --build_plt --output_plt ~/.dialyzer_plt --apps $(ERL_LIBAPPS); true

plts/otp.plt: ~/.dialyzer_plt
	mkdir -p plts && cp ~/.dialyzer_plt plts/otp.plt

plts/deps.plt: plts/otp.plt
	rm -rf `find deps -name ".eunit"`
	$(DIALYZER) --add_to_plt --plt plts/otp.plt --output_plt plts/deps.plt -r deps; true

dialyzer: compile plts/deps.plt
	rm -rf `find apps -name ".eunit"`
	$(DIALYZER) --plt plts/deps.plt -n --no_native -r apps; true


