function [stat] = connectivityanalysis(cfg, data)

% CONNECTIVITYANALYIS computes various measures of connectivity
% between MEG/EEG channels or between source-level timecourse signals.
%
% Use as
%   stat = connectivityanalysis(cfg, data)
%   stat = connectivityanalysis(cfg, timelock)
%   stat = connectivityanalysis(cfg, freq)
% where the first input argument is a configuration structure (see
% below) and the second argument is the output of PREPROCESSING,
% TIMELOCKANLAYSIS or FREQANALYSIS, depending on the connectivity
% measure that you want to compute.
%
% The configuration structure can contain
%   cfg.method  = 'coh', 'plv', 'corr', 'xcorr', 'dtf', 'pdc', 'granger', 'dplv', 'pli', 'psi', 'pcd', ...
%

% Copyright (C) 2009, Robert Oostenveld & Jan-Mathijs Schoffelen
%
% $Log: connectivityanalysis.m,v $
% Revision 1.9  2009/10/28 09:05:03  jansch
% added jackknife for phaseslope index
%
% Revision 1.8  2009/10/19 13:21:33  jansch
% created working version of jackknife estimate for coherence and plv. allowed
% for linear indexing by means of cfg.channelcmb. essentially, this replicates
% the functionality of freqdescriptives
%
% Revision 1.7  2009/10/16 15:03:16  jansch
% in the process of implementing jackknife for coherence (does not work yet)
%
% Revision 1.6  2009/10/12 13:20:27  andbas
% fixed big bug in psi-computation. should be better now
%
% Revision 1.5  2009/10/08 07:35:07  jansch
% added dtf and pdc as method
%
% Revision 1.4  2009/10/01 19:35:02  jansch
% added some real code for 'coh' 'plv' 'granger' and 'psi'
%
% Revision 1.3  2009/09/30 12:48:47  jansch
% some changes
%
% Revision 1.2  2009/08/06 08:30:57  roboos
% added some methods
%
% Revision 1.1  2009/06/23 19:54:02  roboos
% created initial skeleton
%

fieldtripdefs

% check if the input cfg is valid for this function
cfg = checkconfig(cfg, 'trackconfig', 'on');

% set the defaults
if ~isfield(cfg, 'feedback'),   cfg.feedback   = 'none'; end
if ~isfield(cfg, 'channel'),    cfg.channel    = 'all'; end
if ~isfield(cfg, 'channelcmb'), cfg.channelcmb = {};    end
if ~isfield(cfg, 'trials'),     cfg.trials     = 'all'; end
if ~isfield(cfg, 'complex'),    cfg.complex    = 'abs'; end
if ~isfield(cfg, 'jackknife'),  cfg.jackknife  = 'no';  end

hasjack = isfield(data, 'method') && strcmp(data.method, 'jackknife');
hasrpt  = ~isempty(strfind(data.dimord, 'rpt'));
dojack  = strcmp(cfg.jackknife, 'yes');
normrpt = 0; %default, has to be overruled e.g. in plv, because of single
%replicate normalisation

% ensure that the input data is appropriate for the method
switch cfg.method
case {'coh'}
  data    = checkdata(data, 'datatype', {'freqmvar' 'freq'});
  inparam = 'crsspctrm';  
case {'plv'}
  data    = checkdata(data, 'datatype', {'freqmvar' 'freq'});
  inparam = 'crsspctrm';  
  normrpt = 1;
case {'corr' 'xcorr'}
  data = checkdata(data, 'datatype', 'raw');
  %FIXME could also work with frequency domain data: amplitude correlations
case {'granger'}
  data    = checkdata(data, 'datatype', {'mvar' 'freqmvar' 'freq'});
  inparam = 'transfer';
  %FIXME could also work with time domain data
case {'dtf' 'pdc'}
  data    = checkdata(data, 'datatype', {'freqmvar' 'freq'});
  inparam = 'transfer';
case {'psi'}
  data    = checkdata(data, 'datatype', {'freqmvar' 'freq'});
  inparam = 'crsspctrm';
case {'di'}
  %wat eigenlijk?
otherwise
  error('unknown method %s', cfg.method);
end

%FIXME throw an error if cfg.complex~='abs', and dojack==1
%FIXME throw an error if no replicates and cfg.method='plv'

cfg.channel    = channelselection(cfg.channel, data.label);
if ~isempty(cfg.channelcmb), cfg.channelcmb = channelcombination(cfg.channelcmb, cfg.channel, 1); end

if ~isfield(data, inparam),
  dtype = datatype(data);
  switch dtype
  case 'freq'
    if strcmp(inparam, 'crsspctrm')
      if ~isempty(cfg.channelcmb),
        data    = checkdata(data, 'cmbrepresentation', 'sparse', 'channelcmb', cfg.channelcmb);
        
        %use helper function to get linear index from labelcmb pointing to corresponding auto-combinations
        powindx = labelcmb2indx(data.labelcmb); 
      else
        data    = checkdata(data, 'cmbrepresentation', 'full');
        powindx = [];
      end
    end
  otherwise
  end
else
   powindx = [];
end

if normrpt && hasrpt,
  if strcmp(inparam, 'crsspctrm'),
    tmp  = getfield(data, inparam);
    nrpt = size(tmp,1);
    progress('init', cfg.feedback, 'normalising...');
    for k = 1:nrpt
      progress(k/nrpt, 'normalising amplitude of replicate %d from %d to 1\n', k, nrpt);
      tmp(k,:,:,:,:) = tmp(k,:,:,:,:)./abs(tmp(k,:,:,:,:));
    end
    progress('close');
    data = setfield(data, inparam, tmp);
  end
end

%check if jackknife is required
if hasrpt && dojack && hasjack,
  %do nothing
elseif hasrpt && dojack,
  %compute leave-one-outs
  data    = selectdata(data, 'jackknife', 'yes');
  hasjack = 1;
elseif hasrpt
  data   = selectdata(data, 'avgoverrpt', 'yes');
  hasrpt = 0;
else
  %nothing required
end

% compute the desired connectivity
switch cfg.method
case 'coh'
  %coherency  

  tmpcfg           = [];
  tmpcfg.complex   = cfg.complex;
  tmpcfg.feedback  = cfg.feedback;
  tmpcfg.dimord    = data.dimord;
  tmpcfg.powindx   = powindx;
  [datout, varout, nrpt] = coupling_corr(tmpcfg, data.(inparam), hasrpt, hasjack);
  outparam         = 'cohspctrm';

case 'plv'
  %phase locking value

  tmpcfg           = [];
  tmpcfg.complex   = cfg.complex;
  tmpcfg.feedback  = cfg.feedback;
  tmpcfg.dimord    = data.dimord;
  tmpcfg.powindx   = powindx;
  [datout, varout, nrpt] = coupling_corr(tmpcfg, data.(inparam), hasrpt, hasjack);
  outparam         = 'plvspctrm';

case 'corr'
  % pearson's correlation coefficient
case 'xcorr'
  % cross-correlation function
case 'spearman'
  % spearman's rank correlation
case 'granger'
  % granger causality

  
  %FIXME handle replicates, which should be averaged first, unless they contain jackknife samples
  if sum(datatype(data, {'freq' 'freqmvar'})),
    %fs      = cfg.fsample; %FIXME do we really need this, or is this related to how
    %noisecov is defined and normalised?
    fs       = 1;
    datout   = coupling_granger(data.transfer, data.noisecov, data.crsspctrm, fs);
    varout   = [];
    outparam = 'grangerspctrm';
  else
    error('granger for time domain data is not yet implemented');
  end

case 'dtf'
  % directed transfer function

  tmpcfg = []; % for the time being
  hasrpt = ~isempty(strfind(data.dimord, 'rpt'));
  if hasrpt,
    nrpt  = size(data.transfer,1);
    datin = data.transfer;
  else
    nrpt  = 1; 
    datin = reshape(data.transfer, [1 size(data.transfer)]);
  end
  datout   = coupling_dtf(tmpcfg, datin);
  outparam = 'dtfspctrm';

case 'pdc' 
  % partial directed coherence

  tmpcfg = []; % for the time being
  tmpcfg.feedback = cfg.feedback;
  hasrpt = ~isempty(strfind(data.dimord, 'rpt'));
  if hasrpt,
    nrpt  = size(data.transfer,1);
    datin = data.transfer;
  else
    nrpt  = 1;
    datin = reshape(data.transfer, [1 size(data.transfer)]);
  end
  [datout, varout, n] = coupling_pdc(tmpcfg, datin, hasrpt, hasjack);
  outparam = 'pdcspctrm';

case 'pcd'
  % pairwise circular distance
case 'psi'
  % phase slope index
  
  tmpcfg           = [];
  tmpcfg.complex   = cfg.complex;
  tmpcfg.feedback  = cfg.feedback;
  tmpcfg.dimord    = data.dimord;
  tmpcfg.powindx   = powindx;
  tmpcfg.nbin      = nearest(data.freq, data.freq(1)+cfg.bandwidth)-1;
  [datout, varout, nrpt] = coupling_psi(tmpcfg, data.(inparam), hasrpt, hasjack);
  outparam         = 'psispctrm';

case 'di'
  % directionality index
otherwise
  error('unknown method %s', cfg.method);
end

%remove the auto combinations if necessary
if strcmp(inparam, 'crsspctrm') && ~isempty(powindx),
  keep   = powindx(:,1) ~= powindx(:,2);
  datout = datout(keep,:,:,:,:);
  if ~isempty(varout),
    varout = varout(keep,:,:,:,:);
  end
  data.labelcmb = data.labelcmb(keep,:);
end

%create output structure
stat        = [];
stat.label  = data.label;
if isfield(data, 'labelcmb'),
  stat.labelcmb = data.labelcmb;
end
stat.dimord = data.dimord; %FIXME adjust dimord (remove rpt in dojak && hasrpt case)
stat        = setfield(stat, outparam, datout);
if ~isempty(varout),
  stat   = setfield(stat, [outparam,'sem'], (varout/nrpt).^0.5);
end

if isfield(data, 'freq'), stat.freq = data.freq; end
if isfield(data, 'time'), stat.time = data.time; end
if isfield(data, 'grad'), stat.grad = data.grad; end
if isfield(data, 'elec'), stat.elec = data.elec; end

% get the output cfg
cfg = checkconfig(cfg, 'trackconfig', 'off', 'checksize', 'yes');

% add version information to the configuration
try
  % get the full name of the function
  cfg.version.name = mfilename('fullpath');
catch
  % required for compatibility with Matlab versions prior to release 13 (6.5)
  [st, i] = dbstack;
  cfg.version.name = st(i);
end
cfg.version.id = '$Id: connectivityanalysis.m,v 1.9 2009/10/28 09:05:03 jansch Exp $';
% remember the configuration details of the input data
try, cfg.previous = data.cfg; end
% remember the exact configuration details in the output 
stat.cfg = cfg;

%--------------------------------------------------------------
function [c, v, n] = coupling_corr(cfg, input, hasrpt, hasjack)

if nargin==2,
  hasrpt   = 0;
  hasjack  = 0;
elseif nargin==3,
  hasjack  = 0;
end

if length(strfind(cfg.dimord, 'chan'))~=2 && isfield(cfg, 'powindx'),
  %crossterms are not described with chan_chan_therest, but are linearly indexed
  
  siz = size(input);
  if ~hasrpt,
    siz   = [1 siz];
    input = reshape(input, siz);
  end
  
  outsum = zeros(siz(2:end));
  outssq = zeros(siz(2:end));
  
  progress('init', cfg.feedback, 'computing metric...');
  for j = 1:siz(1)
    progress(j/siz(1), 'computing metric for replicate %d from %d\n', j, siz(1));
    p1     = reshape(input(j,cfg.powindx(:,1),:,:,:), siz(2:end));
    p2     = reshape(input(j,cfg.powindx(:,2),:,:,:), siz(2:end));
    outsum = outsum + complexeval(reshape(input(j,:,:,:,:), siz(2:end))./sqrt(p1.*p2), cfg.complex);
    outssq = outssq + complexeval(reshape(input(j,:,:,:,:), siz(2:end))./sqrt(p1.*p2), cfg.complex).^2;
  end
  progress('close');  

elseif length(strfind(cfg.dimord, 'chan'))==2,
  %crossterms are described by chan_chan_therest 
 
  siz = size(input);
  if ~hasrpt,
    siz   = [1 siz];
    input = reshape(input, siz);
  end

  outsum = zeros(siz(2:end));
  outssq = zeros(siz(2:end));
  progress('init', cfg.feedback, 'computing metric...');
  for j = 1:siz(1)
    progress(j/siz(1), 'computing metric for replicate %d from %d\n', j, siz(1));
    p1  = zeros([siz(2) 1 siz(4:end)]);
    p2  = zeros([1 siz(3) siz(4:end)]);
    for k = 1:siz(2)
      p1(k,1,:,:,:,:) = input(j,k,k,:,:,:,:);
      p2(1,k,:,:,:,:) = input(j,k,k,:,:,:,:);
    end
    p1     = p1(:,ones(1,siz(3)),:,:,:,:);
    p2     = p2(ones(1,siz(2)),:,:,:,:,:);
    outsum = outsum + complexeval(reshape(input(j,:,:,:,:,:,:), siz(2:end))./sqrt(p1.*p2), cfg.complex);
    outssq = outssq + complexeval(reshape(input(j,:,:,:,:,:,:), siz(2:end))./sqrt(p1.*p2), cfg.complex).^2;
  end
  progress('close');

end

n = siz(1);
c = outsum./n;

if hasrpt,
  if hasjack
    bias = (n-1).^2;
  else
    bias = 1;
  end
  
  v = bias*(outssq - (outsum.^2)./n)./(n - 1);
else 
  v = [];
end

%-------------------------------------------------------------
function [c, v, n] = coupling_psi(cfg, input, hasrpt, hasjack)

if nargin==2,
  hasrpt   = 0;
  hasjack  = 0;
elseif nargin==3,
  hasjack  = 0;
end

if length(strfind(cfg.dimord, 'chan'))~=2 && isfield(cfg, 'powindx'),
  %crossterms are not described with chan_chan_therest, but are linearly indexed
  
  siz = size(input);
  if ~hasrpt,
    siz   = [1 siz];
    input = reshape(input, siz);
  end
  
  outsum = zeros(siz(2:end));
  outssq = zeros(siz(2:end));
  pvec   = [2 setdiff(1:numel(siz),2)];  

  progress('init', cfg.feedback, 'computing metric...');
  %first compute coherency and then phaseslopeindex
  for j = 1:siz(1)
    progress(j/siz(1), 'computing metric for replicate %d from %d\n', j, siz(1));
    c      = reshape(input(j,:,:,:,:), siz(2:end));
    p1     = abs(reshape(input(j,cfg.powindx(:,1),:,:,:), siz(2:end)));
    p2     = abs(reshape(input(j,cfg.powindx(:,2),:,:,:), siz(2:end)));
    p      = ipermute(phaseslope(permute(c./sqrt(p1.*p2), pvec), cfg.nbin), pvec);
    
    outsum = outsum + p;
    outssq = outssq + p.^2;
  end
  progress('close');  

else %if length(strfind(cfg.dimord, 'chan'))~=2,
  %crossterms are described by chan_chan_therest 
 
  siz = size(input);
  if ~hasrpt,
    siz   = [1 siz];
    input = reshape(input, siz);
  end

  outsum = zeros(siz(2:end));
  outssq = zeros(siz(2:end));
  pvec   = [3 setdiff(1:numel(siz),3)];  
  
  progress('init', cfg.feedback, 'computing metric...');
  for j = 1:siz(1)
    progress(j/siz(1), 'computing metric for replicate %d from %d\n', j, siz(1));
    p1  = zeros([siz(2) 1 siz(4:end)]);
    p2  = zeros([1 siz(3) siz(4:end)]);
    for k = 1:siz(2)
      p1(k,1,:,:,:,:) = input(j,k,k,:,:,:,:);
      p2(1,k,:,:,:,:) = input(j,k,k,:,:,:,:);
    end
    c  = reshape(input(j,:,:,:,:,:,:), siz(2:end));
    p1 = p1(:,ones(1,siz(3)),:,:,:,:);
    p2 = p2(ones(1,siz(2)),:,:,:,:,:);
    %outsum = outsum + complexeval(reshape(input(j,:,:,:,:,:,:), siz(2:end))./sqrt(p1.*p2), cfg.complex);
    %outssq = outssq + complexeval(reshape(input(j,:,:,:,:,:,:), siz(2:end))./sqrt(p1.*p2), cfg.complex).^2;
    
    outsum = outsum + ipermute(phaseslope(permute(c./sqrt(p1.*p2),pvec),cfg.nbin),pvec);
    outssq = outssq + ipermute(phaseslope(permute(c./sqrt(p1.*p2),pvec),cfg.nbin),pvec).^2;
  end
  progress('close');

end

n = siz(1);
c = outsum./n;

if hasrpt,
  if hasjack
    bias = (n-1).^2;
  else
    bias = 1;
  end
  
  v = bias*(outssq - (outsum.^2)./n)./(n - 1);
else 
  v = [];
end


%----------------------------------------
function [pdc, pdcvar, n] = coupling_pdc(cfg, input, hasrpt, hasjack)

if nargin==2,
  hasrpt   = 0;
  hasjack  = 0;
elseif nargin==3,
  hasjack  = 0;
end

%crossterms are described by chan_chan_therest 
 
siz = size(input);
if ~hasrpt,
  %siz   = [1 siz];
  %input = reshape(input, siz);
  %FIX THIS upstairs
end
n = siz(1);

outsum = zeros(siz(2:end));
outssq = zeros(siz(2:end));

%computing pdc is easiest on the inverse of the transfer function
pdim     = prod(siz(4:end));
tmpinput = reshape(input, [siz(1:3) pdim]);
progress('init', cfg.feedback, 'inverting the transfer function...');
for k = 1:n
  progress(k/n, 'inverting the transfer function for replicate %d from %d\n', k, n);
  tmp = reshape(tmpinput(k,:,:,:), [siz(2:3) pdim]);
  for m = 1:pdim
    tmp(:,:,m) = inv(tmp(:,:,m));
  end
  tmpinput(k,:,:,:) = tmp;
end
progress('close');
input = reshape(tmpinput, siz);

progress('init', cfg.feedback, 'computing metric...');
for j = 1:n
  progress(j/n, 'computing metric for replicate %d from %d\n', j, n);
  invh   = reshape(input(j,:,:,:,:), siz(2:end));
  den    = sum(abs(invh).^2,1);
  tmppdc = abs(invh)./sqrt(repmat(den, [siz(2) 1 1 1 1]));
  %if ~isempty(cfg.submethod), tmppdc = baseline(tmppdc, cfg.submethod, baselineindx); end
  outsum = outsum + tmppdc;
  outssq = outssq + tmppdc.^2;
end
progress('close');

pdc = outsum./n;

if hasrpt,
  if hasjack
    bias = (n-1).^2;
  else
    bias = 1;
  end
  
  pdcvar = bias*(outssq - (outsum.^2)./n)./(n - 1);
else 
  pdcvar = [];
end

%----------------------------------------
function [dtf] = coupling_dtf(cfg, input)

siz    = size(input);
nrpt   = siz(1);
sumdtf = zeros(siz(2:end));
sqrdtf = zeros(siz(2:end));

for n = 1:nrpt
  tmph   = reshape(input(n,:,:,:,:), siz(2:end));
  den    = sum(abs(tmph).^2,2);
  tmpdtf = abs(tmph)./sqrt(repmat(den, [1 siz(2) 1 1 1]));
  %if ~isempty(cfg.submethod), tmpdtf = baseline(tmpdtf, cfg.submethod, baselineindx); end
  sumdtf = sumdtf + tmpdtf;
  sqrdtf = sqrdtf + tmpdtf.^2;
end
dtf = sumdtf./nrpt;

if nrpt>1, %FIXME this is strictly only true for jackknife, otherwise other bias is needed
  bias   = (nrpt - 1).^2;
  dtfvar = bias.*(sqrdtf - (sumdtf.^2)/nrpt)./(nrpt-1);
  dtfsem = sqrt(dtfvar./nrpt);
end

%--------------------------------------------------------------------
function [granger, v, n] = coupling_granger(transfer,noisecov,crsspctrm,fs)

%Usage: causality = hz2causality(H,S,Z,fs);
%Inputs: transfer  = transfer function,
%        crsspctrm = 3-D spectral matrix;
%        noisecov  = noise covariance, 
%        fs        = sampling rate
%Outputs: granger (Granger causality between all channels)
%               : auto-causality spectra are set to zero
% Reference: Brovelli, et. al., PNAS 101, 9849-9854 (2004).
%M. Dhamala, UF, August 2006.

%FIXME speed up code and check

H  = transfer;
Z  = noisecov;
S  = crsspctrm;

Nc = size(H,2);
%clear S; for k = 1:size(H,3), h = squeeze(H(:,:,k)); S(:,:,k) = h*Z*h'/fs; end;
for ii = 1: Nc,
    for jj = 1: Nc,
          if ii ~=jj,
              zc = Z(jj,jj) - Z(ii,jj)^2/Z(ii,ii);
              numer = abs(S(ii,ii,:));
              denom = abs(S(ii,ii,:)-zc*abs(H(ii,jj,:)).^2/fs);
              granger(jj,ii,:) = log(numer./denom);
          end
    end
    granger(ii,ii,:) = 0;%self-granger set to zero
end

%----------------------------------------
function [indx] = labelcmb2indx(labelcmb)

%identify the auto-combinations
ncmb = size(labelcmb,1);
indx = zeros(ncmb,2);
for k = 1:ncmb
  chan = labelcmb{k,1};
  hit  = strcmp(chan,labelcmb{k,2});
  if ~isempty(hit)
    sel1 = strmatch(chan, labelcmb(:,1), 'exact');
    indx(sel1,1) = k;
    sel2 = strmatch(chan, labelcmb(:,2), 'exact');
    indx(sel2,2) = k;
  end
end

%----------------------------------
function [c] = complexeval(c, str);

switch str
  case 'complex'
    %do nothing
  case 'abs'
    c = abs(c);
  case 'angle'
    c = angle(c);
  case 'imag'
    c = imag(c);
  case 'real'
    c = real(c);
otherwise
  error('cfg.complex = ''%s'' not supported', cfg.complex);
end

%---------------------------------------
function [y] = phaseslope(x, n)

m = size(x, 1); %total number of frequency bins
y = zeros(size(x));
x(1:end-1,:,:,:,:) = conj(x(1:end-1,:,:,:,:)).*x(2:end,:,:,:,:);
for k = 1:m
  begindx = max(1,k-n);
  endindx = min(m,k+n);
  y(k,:,:,:,:) = imag(sum(x(begindx:endindx,:,:,:,:)));
end



%if ~isfield(cfg, 'cohmethod'), cfg.cohmethod = 'coh';           end;
%if ~iscell(cfg.cohmethod),     cfg.cohmethod = {cfg.cohmethod}; end;
%if ~isfield(cfg, 'submethod'), cfg.submethod = '';              end;
%if ~isempty(cfg.submethod) && ~isfield(cfg, 'baseline'),
%  cfg.baseline = 'all';
%end
%
%if isfield(cfg, 'baseline') && strcmp(cfg.baseline, 'all'),
%  cfg.baseline = [freq.time(1) freq.time(end)];
%end
%
%if isfield(cfg, 'baseline'),
%  baselineindx = [nearest(freq.time, cfg.baseline(1)) nearest(freq.time, cfg.baseline(2))];
%end
%
%
%if hasrpt, 
%  nrpt = size(freq.cumtapcnt, 1); 
%else
%  nrpt = 1;
%  dum  = zeros([1 size(freq.crsspctrm)]); dum(1,:,:,:,:) = freq.crsspctrm; freq.crsspctrm = dum;
%  dum  = zeros([1 size(freq.powspctrm)]); dum(1,:,:,:,:) = freq.powspctrm; freq.powspctrm = dum;
%  dum  = zeros([1 size(freq.transfer) ]); dum(1,:,:,:,:) = freq.transfer;  freq.transfer  = dum;
%  dum  = zeros([1 size(freq.itransfer)]); dum(1,:,:,:,:) = freq.itransfer; freq.itransfer = dum;
%  dum  = zeros([1 size(freq.noisecov) ]); dum(1,:,:,:,:) = freq.noisecov;  freq.noisecov  = dum;
%  hasrpt = 1;
%end
%if hastim, 
%  ntoi = length(freq.time);       
%else
%  ntoi = 1;
%end
%nfoi  = length(freq.freq);
%nchan = length(freq.label);
%ncmb  = size(freq.labelcmb,1);
%ntap  = freq.cumtapcnt(1);
%
%for m = 1:length(cfg.cohmethod)
%  switch cfg.cohmethod{m}
%    case {'coh' 'coh2'}
%      for k = 1:ncmb
%        cmbindx(k,1) = match_str(freq.label,freq.labelcmb(k,1));
%        cmbindx(k,2) = match_str(freq.label,freq.labelcmb(k,2));
%      end
%
%      sumcohspctrm = zeros([ncmb  nfoi ntoi]);
%      sumpowspctrm = zeros([nchan nfoi ntoi]);
%      sqrcohspctrm = zeros([ncmb  nfoi ntoi]);
%      sqrpowspctrm = zeros([nchan nfoi ntoi]);
%      warning off;
%      for n = 1:nrpt
%        crsspctrm    = abs(reshape(mean(freq.crsspctrm(n,:,:,:,:),5), [ncmb  nfoi ntoi]));
%        tmppowspctrm = abs(reshape(mean(freq.powspctrm(n,:,:,:,:),5), [nchan nfoi ntoi]));
%        
%	if strcmp(cfg.cohmethod{m}, 'coh'),
%	  tmpcohspctrm = crsspctrm./sqrt(abs(tmppowspctrm(cmbindx(:,1),:,:,:)).*abs(tmppowspctrm(cmbindx(:,2),:,:,:)));
%        else
%          tmph = reshape(freq.transfer(n,:,:,:,:), [nchan nchan nfoi ntoi ntap]);
%	  for flop = 1:nfoi
%	    for tlop = 1:ntoi
%	      dum                       = tmph(:,:,flop,tlop)*tmph(:,:,flop,tlop)';
%	      tmpcohspctrm(:,flop,tlop) = reshape(dum./sqrt(abs(diag(dum))*abs(diag(dum))'), [ncmb 1]);
%	    end
%	  end
%	end
%	
%	if ~isempty(cfg.submethod), tmpcohspctrm = baseline(tmpcohspctrm, cfg.submethod, baselineindx); end
%        if ~isempty(cfg.submethod), tmppowspctrm = baseline(tmppowspctrm, cfg.submethod, baselineindx); end
%	sumcohspctrm = tmpcohspctrm    + sumcohspctrm;
%	sqrcohspctrm = tmpcohspctrm.^2 + sqrcohspctrm;
%	sumpowspctrm = tmppowspctrm    + sumpowspctrm;
%	sqrpowspctrm = tmppowspctrm.^2 + sqrpowspctrm;
%      end
%      warning on;
%      cohspctrm = sumcohspctrm./nrpt;
%      powspctrm = sumpowspctrm./nrpt;
%
%      if nrpt>1,
%        bias         = (nrpt - 1)^2;
%        cohspctrmvar = bias.*(sqrcohspctrm - (sumcohspctrm.^2)/nrpt)./(nrpt-1);
%        powspctrmvar = bias.*(sqrpowspctrm - (sumpowspctrm.^2)/nrpt)./(nrpt-1);
%        cohspctrmsem = sqrt(cohspctrmvar./nrpt);
%        powspctrmsem = sqrt(powspctrmvar./nrpt);
%      end
%    case 'dtf'
%      sumdtf = zeros(ncmb, nfoi, ntoi, ntap);
%      sqrdtf = zeros(ncmb, nfoi, ntoi, ntap);
%      for n = 1:nrpt
%        tmph   = reshape(freq.transfer(n,:,:,:,:), [nchan nchan nfoi ntoi ntap]);
%        den    = sum(abs(tmph).^2,2);
%        tmpdtf = abs(tmph)./sqrt(repmat(den, [1 nchan 1 1 1]));
%        tmpdtf = reshape(tmpdtf, [ncmb nfoi ntoi ntap]);
%        if ~isempty(cfg.submethod), tmpdtf = baseline(tmpdtf, cfg.submethod, baselineindx); end
%        sumdtf = sumdtf + tmpdtf;
%	sqrdtf = sqrdtf + tmpdtf.^2;
%      end
%      dtf = sumdtf./nrpt;
%
%      if nrpt>1,
%        bias   = (nrpt - 1).^2;
%	dtfvar = bias.*(sqrdtf - (sumdtf.^2)/nrpt)./(nrpt-1);
%	dtfsem = sqrt(dtfvar./nrpt);
%      end
%    case 'pdc'
%      sumpdc = zeros(ncmb, nfoi, ntoi, ntap);
%      sqrpdc = zeros(ncmb, nfoi, ntoi, ntap);
%      for n = 1:nrpt
%        invh = reshape(freq.itransfer(n,:,:,:,:), [nchan nchan nfoi ntoi ntap]);
%        %invh = zeros(size(h));
%        %for j = 1:nfoi
%        %  for k = 1:ntoi
%	%    invh(:,:,j,k) = inv(h(:,:,j,k));
%	%  end
%        %end
%        den    = sum(abs(invh).^2,1);
%        tmp    = abs(invh)./sqrt(repmat(den, [nchan 1 1 1 1]));
%        tmppdc = reshape(tmp, [ncmb nfoi ntoi ntap]);
%        if ~isempty(cfg.submethod), tmppdc = baseline(tmppdc, cfg.submethod, baselineindx); end
%	sumpdc = sumpdc + tmppdc;
%	sqrpdc = sqrpdc + tmppdc.^2;
%      end
%      pdc = sumpdc./nrpt;
%      
%      if nrpt>1,
%        bias   = (nrpt - 1).^2;
%	pdcvar = bias.*(sqrpdc - (sumpdc.^2)/nrpt)./(nrpt-1);
%	pdcsem = sqrt(pdcvar./nrpt);
%      end
%    otherwise
%      error('unknown cohmethod specified in cfg.cohmethod');
%  end
%end
%
%%---create output-structure
%fd = [];
%fd.label = freq.label;
%fd.labelcmb = freq.labelcmb;
%fd.freq     = freq.freq;
%if hastim, fd.time = freq.time; end
%fd.nobs     = nrpt;
%fd.dimord   = 'chan_freq_time';
%
%try, fd.pdc       = pdc;       end
%try, fd.pdcsem    = pdcsem;    end
%try, fd.dtf       = dtf;       end
%try, fd.dtfsem    = dtfsem;    end
%try, fd.cohspctrm = cohspctrm; end
%try, fd.powspctrm = powspctrm; end
%try, fd.cohspctrmsem = cohspctrmsem; end
%try, fd.powspctrmsem = powspctrmsem; end
%try, cfg.previous    = freq.cfg;     end
%fd.cfg = cfg;
%
%%---subfunction to do baseline correction
%function [output] = baseline(input, method, baseline)
%
%switch method,
%  case 'relchange'
%    b      = mean(input(:,:,baseline(1):baseline(2)),3);
%    output = input./repmat(b, [1 1 size(input,3) 1]) - 1;
%  case 'diff'
%    b      = mean(input(:,:,baseline(1):baseline(2)),3);
%    output = input-repmat(b, [1 1 size(input,3) 1]);
%  otherwise
%    error('specified baseline-method is not yet implemented');
%end
