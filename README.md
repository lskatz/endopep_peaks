# Endopep peaks

Simplifies a multitab Bruker spreadsheet into a single spreadsheet

## Installation

    mkdir ~/bin
    cd ~/bin
    git clone https://github.com/lskatz/endopep_peaks.git
    cd endopep_peaks
    source scripts/environment.sh
    cpanm -l . --installdeps .
    perl Makefile.PL
    make

## Usage

Preparation; loading the environment

    source ~/bin/endopep_peaks/scripts/environment.sh

Sends a tsv file to stdout

    parseBruker.pl exampleData/02.24.20/022420_JD_raw.xlsx > spreadsheet.tsv

Usage menu

    parseBruker.pl --help

Version
    
    parseBruker.pl --version

## Output

The spreadsheet will have a header row of

* plate
* sample
* inferred\_type (version >= 3.5)
* acquisition
* A\_cleavage\_1
* SN\_A\_cleavage\_1
* etc for each cleavage site and intact

and rows for each acquisition.

Values will have a dot `.` if the values are unknown.

