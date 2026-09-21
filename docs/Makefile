TARGETS := pisg-doc.txt pisg-doc.html pisg-faq.html pisg-formats.html pisg.1
VERSION := $(shell grep "version =>" ../modules/Pisg.pm | sed 's/[^"]*"\([^"]*\)".*/\1/; s/+CVS//')

all: $(TARGETS)

pisg-doc.xml: .version
.version: ../modules/Pisg.pm
	perl -i -pe 's/(<title>pisg ).*(documentation<\/title>)/$${1}$(VERSION) $${2}/' pisg-doc.xml
	touch .version

pisg-doc.txt: pisg-doc.xml
	docbook2txt pisg-doc.xml
	mv pisg-doc.txt pisg-tmp.txt
	cat pisg-tmp.txt | ./modifytxt.pl > pisg-doc.txt
	rm -f pisg-tmp.txt

# One self-contained page with the example configuration at the end.
pisg-doc.html: pisg-doc.xml
	python3 xml2html.py pisg-doc.xml pisg-doc.html

pisg-faq.html: pisg-faq.txt
	a2x -f xhtml pisg-faq.txt

pisg-formats.html: FORMATS
	a2x -f xhtml FORMATS
	mv FORMATS.html pisg-formats.html

pisg.1: pisg.sgml
	docbook2man $< > $@

clean:
	rm -f $(TARGETS) .version

.PHONY: all clean

# vim:noexpandtab:
