HXP=../htmlXPress.pl
OUT=results

htdocs = $(wildcard *.html *.php *.css *.js *.xml)

all : \
	$(addprefix $(OUT)/,$(htdocs))

clean :
	$(RM) $(OUT)/*
	
.PHONY : all
.DEFAULT : all
.SUFFIXES:


# Dependency rules

$(OUT)/*.html : $(OUT)/example.css


# The work rules

$(OUT)/% : %
	$(HXP) -out $(@D) $<
