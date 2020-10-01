#!/usr/bin/env perl 

use warnings;
use strict;
use Data::Dumper;
$Data::Dumper::Sortkeys = 1;
use Getopt::Long;
use File::Basename qw/basename/;

# Bring in perl libraries
use FindBin qw/$RealBin/;
use lib "$RealBin/../lib/perl5";

# Optional modules that are not standard
use Spreadsheet::XLSX;
#use Excel::Writer::XLSX;
use Array::IntSpan;

our $VERSION = '3.5.0';

# Expected peaks per serotype
my $peakRanges = Array::IntSpan->new();

# A
$peakRanges->set_range(3280.7,3293.7,"A_intact");
$peakRanges->set_range(996.8 ,1000.8,"A_cleavage_1");
$peakRanges->set_range(2302.9,2312.1,"A_cleavage_2");
# B
$peakRanges->set_range(4018.4,4034.6,"B_intact");
$peakRanges->set_range(1756.5,1763.5,"B_cleavage_1");
$peakRanges->set_range(2277.7,2286.9,"B_cleavage_2");
# E
$peakRanges->set_range(3607.8,3622.2,"E_intact");
$peakRanges->set_range(1129.2,1133.8,"E_cleavage_1");
$peakRanges->set_range(2493.6,2503.6,"E_cleavage_2");
# F
$peakRanges->set_range(5100.8,5121.2,"F_intact");
$peakRanges->set_range(1342.5,1347.9,"F_cleavage_1");
$peakRanges->set_range(3777.3,3792.5,"F_cleavage_2");
# F5
$peakRanges->set_range(5100.8,5121.2,"F5_intact");
$peakRanges->set_range(1870.3,1877.7,"F5_cleavage_1");
$peakRanges->set_range(3248.5,3261.5,"F5_cleavage_2");

my @subtype      = qw(A B E F F5);
my @cleavageType = qw(cleavage_1 cleavage_2 intact);
# Combine @subtype and @cleavageType into a header
my @typingHeader;
for my $type(@subtype){
  for my $cleavageType(@cleavageType){
    push(@typingHeader, $type."_".$cleavageType);
    push(@typingHeader, "SN_".$type."_".$cleavageType);
  }
}

local $0 = basename $0;
sub logmsg{local $0=basename $0; print STDERR "$0: @_\n";}
exit(main());

sub main{
  my $settings={};
  GetOptions($settings,qw(version help)) or die $!;
  version() if($$settings{version});
  usage() if($$settings{help} || !@ARGV);

  # print off the output header
  print "plate\tsample\tinferred_type\tacquisition\t";
  print join("\t",@typingHeader);
  print "\n";

  # Start off the basic workflow
  for my $spreadsheet(@ARGV){
    my $tsv = readRawSpreadsheet($spreadsheet, $settings);
    
    for my $plate(sort keys(%$tsv)){
      my $plateEntries = $$tsv{$plate};
      # Loop through the samples but sort them alphabetically
      for my $sample(sort {$a cmp $b} keys(%$plateEntries)){
        my $sampleInfo = $$plateEntries{$sample};
        
        # How many acquisitions are there?
        my $numAcquisitions = 0;
        for my $peak(sort keys(%$sampleInfo)){
          my $thisPeakAcquisitionCount = scalar(@{ $$sampleInfo{$peak} });
          if($thisPeakAcquisitionCount > $numAcquisitions){
            $numAcquisitions = $thisPeakAcquisitionCount;
          }
        }
        
        # Find the first acquisition's type and label it as the reference.
        # If all acquisitions agree, then all good.
        # If not, then label the type as "inconclusive"
        my $inferredType = inferType($sampleInfo, 0, $settings);
        my %allTypes = map{ $_=>1 } split(/,/, $inferredType);
        my $is_inconclusive = 0;
        for(my $acquisition=0; $acquisition < $numAcquisitions; $acquisition++){
          my $acquisitionType = inferType($sampleInfo, $acquisition, $settings);
          if($inferredType ne $acquisitionType){
            $is_inconclusive = 1;
            for my $type(split(",", $acquisitionType)){
              $allTypes{$type}++;
            }
          }
        }
        # If inconclusive, rename the type as "inconclusive" and add
        # on all possible types.
        if($is_inconclusive){
          my @uniqueType = sort{$a cmp $b} keys(%allTypes);
          $inferredType = "inconclusive(".join(",",@uniqueType).")";
        }
        
        # the sample has multiple acquisitions in the data structure,
        # so there will be one row printed per acquisition.
        for(my $acquisition=0; $acquisition < $numAcquisitions; $acquisition++){
          print join("\t", $plate, $sample, $inferredType, ($acquisition+1));
          # Increment by two because the header has both the peak and peak_SN keys
          for(my $i=0;$i<@typingHeader;$i+=2){
            # Get the peaks hash (signal-to-noise and peak)
            my $peakInfo = $$sampleInfo{$typingHeader[$i]}[$acquisition];
            # Set a default for the hash if it's missing for this type
            $peakInfo ||= {peak=>".", SN=>"."};
            print "\t".$$peakInfo{peak}."\t".$$peakInfo{SN};
          }
          print "\n";
        }
      }
    }

  }

  return 0;
}

sub readRawSpreadsheet{
  my($spreadsheet, $settings) = @_;
  
  # https://metacpan.org/pod/Spreadsheet::XLSX
  my $excel = Spreadsheet::XLSX->new($spreadsheet);
  # Must remove randomness
  $$excel{Worksheet} = [sort {$$a{path} cmp $$b{path}} @{$$excel{Worksheet}}];

  my %peakInfo;

  foreach my $sheet (@{$excel->{Worksheet}}){
    #printf("Sheet: %s\n", $sheet->{Name});
    my %tsv;

    # Initialize variables for columns in the
    # single-sheet intermediate file
    my($date, $plate, $sample,$Peak_1_A, $sn_Peak_1_A, $Peak_2_A, $sn_Peak_2_A, $Intact_A, $sn_Intact_A, $Peak_1_B, $sn_Peak_1_B, $Peak_2_B, $sn_Peak_2_B, $Intact_B, $sn_Intact_B, $Peak_1_E, $sn_Peak_1_E, $Peak_2_E, $sn_Peak_2_E, $Intact_E, $sn_Intact_E, $Peak_1_F, $sn_Peak_1_F, $Peak_2_F, $sn_Peak_2_F, $Intact_F, $sn_Intact_F);

    my @header; #header columns

    $sheet -> {MaxRow} ||= $sheet -> {MinRow};
    $sheet -> {MaxCol} ||= $sheet -> {MinCol};
        
    # Loop through the rows
    $sheet -> {MaxRow} ||= $sheet -> {MinRow};
    ROW:
    for(my $row=$sheet->{MinRow}; $row<=$sheet->{MaxRow}; $row++){
      
      # mark if we are looking at the header row
      my $rowkey; # index of this row will be m/z
      my %tsvrow; # This TSV's row
        
      # Loop through the columns of the row
      COL:
      for(my $col=$sheet->{MinCol}; $col<=$sheet->{MaxCol}; $col++){
               
        my $cell = $sheet->{Cells}[$row][$col];
        # I don't care much about blank cells for this analysis
        next if(!$cell);

        # Extract the cell's value for readability
        my $value = $$cell{Val};
        $value =~ s/^\s+|\s+$//g; # whitespace trim

        # Parse the line with Spectrum: D:\Data\CLIA\2020\02-21-20\Plate 169380\2000001 Pl-6-A\0_A3\1\1SLin
        if($value =~ /Plate\s+(.+?)\\(.+?)\\/){
          $plate  = $2;
          $sample = $1;
        }

        # We're looking at the header row if we come across m/z
        if(lc($value) eq 'm/z'){
          @header = map{$_->{Val}} @{ $$sheet{Cells}[$row] };
          next ROW;
        }

        # If headers are already defined, then we're looking at values
        # and let's set those values in a hash.
        if(@header){
          my @tsvValue;
          while($col <= $sheet->{MaxCol}){
            $tsvValue[$col] = $sheet->{Cells}[$row][$col]{Val};
            $tsvValue[$col] //= "";
            $col++;
          }
          @tsvrow{@header} = @tsvValue;
          $tsvrow{row} = $row;
          $tsv{$tsvValue[0]} = \%tsvrow;
          #push(@{ $tsv{$tsvValue[0]} }, \%tsvrow);
          #die Dumper $tsvValue[0],\%tsvrow;
          next ROW;
        }
      }

    }

    if(keys(%tsv)){
      if(!$plate){
        die "ERROR: did not find plate ID on tab ".$sheet->{Name};
      }
      if(!$sample){
        die "ERROR: did not find bot ID on tab ".$sheet->{Name};
      }

      # There are multiple acquisitions per sample per
      # plate and so it needs to be captured in an array.
      push(@{ $peakInfo{$sample}{$plate} }, \%tsv);
    }
  }
  #print Dumper \%peakInfo;exit 0;
  #die Dumper keys(%{ $peakInfo{157016} });

  # Turn this into a 25+ column format with each peak info shown on each plate/sample combo line
  my %finalTsv;
  while(my($plate, $plateInfo) = each(%peakInfo)){
    while(my($sampleAndSerotype, $sampleInfoArr) = each(%$plateInfo)){
      my($sample, $serotype) = split(/\-/, $sampleAndSerotype);
      for my $sampleInfo(@$sampleInfoArr){
        my @peak;
        my @sortedPeakInfo = sort {
          $$sampleInfo{$a}{row}||=0;
          $$sampleInfo{$b}{row}||=0;
          $$sampleInfo{$a}{row} <=> $$sampleInfo{$b}{row}
        } values(%$sampleInfo);
        for my $peak(@sortedPeakInfo){
          # Find which type this belongs to based on ranges of m/z
          my $type = $peakRanges->lookup($$peak{'m/z'});
          # If not found in the ranges, UNDEFINED
          next if(!defined($type));
          $type||="UNDEFINED_PEAK";

          # Record this peak under the right type
          my %info = (
            peak  => $$peak{'m/z'},
            SN    => $$peak{SN},
            type  => $type,
            serotype => $serotype,
          );

          # There are multiple acquisitions per sample per
          # plate and so each peak could have multiple
          # values; transform these data into an array.
          #$finalTsv{$plate}{$sample}{$type} = \%info;
          push(@{ $finalTsv{$plate}{$sample}{$type} }, \%info);

          #TODO what to do if multiple undefined peaks? Do we care?
        }
      }
      #die Dumper \%finalTsv;
    }
  }

  # Keep the data structure stable by sorting
  while(my($plate, $plateInfo) = each(%finalTsv)){
    while(my($sample, $sampleInfo) = each(%$plateInfo)){
      while(my($type, $serotypeInfo) = each(%$sampleInfo)){
        $finalTsv{$plate}{$sample}{$type} =
            [sort {$$b{peak} <=> $$a{peak} || $$a{SN} <=> $$b{SN}} @{ $finalTsv{$plate}{$sample}{$type} }];
      }
    }
  }
  #print Dumper \%finalTsv; exit 0;

  return \%finalTsv;
}

# A sample is positive for a serotype if at least one of the peaks for cleaved products of that serotype is present, with a S/N >10.
# The settings on the Bruker only allow the program to call peaks if the S/N is >10, so everything we see included in the raw Excel spreadsheets should have S/N >10.
# And yes, there could be multiple inferences.
sub inferType{
  my($peaks, $acquisition, $settings) = @_;

  my %type;

  for my $peak(sort keys(%$peaks)){
    next if($peak !~ /cleavage/i);
    # All acquisitions must agree with each other and so this array
    # of types will be checked for consistency.
    my $peakInfo = $$peaks{$peak}[$acquisition];

    # If there isn't even a signal for this peak, skip.
    next if(!$$peakInfo{SN});
    
    # Results shouldn't even get to this point if Signal to noise is less
    # than 10, but just to be sure.
    next if($$peakInfo{SN} <= 10);
    # Can't determine serotype if this peak doesn't even fall in the 
    # right range for a serotype.
    next if(!$$peakInfo{serotype});
    
    $type{ $$peakInfo{serotype} }++;
  }

  # Have _something_ if nothing was detected
  if(!keys(%type)){
    $type{"no-serotype-signal"}++;
  }

  my @typeArr = sort{$a cmp $b} keys(%type);

  my $str = join(",", @typeArr);
  return $str;
}

sub version{
  print "$0 $VERSION";
  exit 0;
}

sub usage{
  print
  "$0: runs the endopep peaks workflow
  Usage: $0 [options] spreadsheet.xlsx [spreadsheet2.xlsx...]
  --help     This useful help menu
  --version  Print the version and exit
";
  exit 0;
}

