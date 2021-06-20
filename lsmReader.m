function LSMdata = lsmReader(filename, varargin)
% this function has been written specifically to handle time-series line
% scan recordings from Zeiss LSM microscopes, particularly where the image
% has been compressed using lossless LZW compression.

% lzw decompression is handled through calls to separate C++ functions
% Native Matlab code to perform this task is provided in the Github repo 
% containing this function but was found to be ~2 orders of magnitude
% slower


% Some notes on the Zeiss LSM file format:
% The first 8 bytes are a standard TIFF file header
% (see tiff6.0 specification document for full details)
% Each 12-byte IFD entry has the following format: 
%       Bytes 0-1: Tag that identifies the field. 
%       Bytes 2-3: The field type. 
%       Bytes 4-7: Count. 
%       Bytes 8-11: Value or offset. Byte count of the indicated types. 
% Types 1 = BYTE, 2 = ASCII (8-bit),3 = SHORT (16-bit), 4 = LONG(32-bit).  
% If the count is 1, then bytes 8-11 store the value, otherwise they store 
% the offset pointing to the position where the value is stored.

% LSM files are structured as follows: 
% header -> IFDs -> real image/thumbnails. 
% The first IFD has the entry 34412 which points to LSM-specific data. 
%-------------------------------------------------------------------------


% the following code (including C++ functions) is based on lsmread by
% joe-of-all-trades (https://github.com/joe-of-all-trades/lsmread/blob/master/lsmread.m)
% and LSMToolbox by Peter Li, which is written in Java and bundled with 
% current ImageJ builds 

%%
    fID = fopen(filename);

    % First 8 bytes: file header
    % Bytes 0-1:    byte order
    byteOrder = fread(fID, 2, '*char')';
    if (strcmp(byteOrder, 'II'))
        byteOrder = 'ieee-le';
    elseif (strcmp(byteOrder,'MM'))
        byteOrder = 'ieee-be';
    else
        error('File header error; this is not a TIFF file');
    end

    % Bytes 2-3: Tiff version (Should always be 42)
    tiffID = fread(fID, 1, 'uint16', byteOrder);
    if (tiffID ~= 42)
        error('File header error; this is not a TIFF file');
    end

    % Bytes 4-7: offset to first Image File Directory (IFD)
    ifdPos = fread(fID, 1, 'uint32', byteOrder);
    fseek(fID, ifdPos, 'bof');

    imgByteOffsets = cell(25,1);
    ifdIndex = 0;
    IFD = cell(1,1);

    while ifdPos ~= 0 
          ifdIndex = ifdIndex + 1;
          imgByteOffsets{ifdIndex} = ifdPos;
          fseek(fID,ifdPos, 'bof');
          % First two bytes of each IFD specify number of IFD entries.
          numEntries = fread(fID, 1, 'uint16', byteOrder);
          entryPos = ifdPos + 2;  
          % Each IFD entry is 12 bytes long.
          fseek(fID, ifdPos + (12 * numEntries + 2), 'bof');  
          % The last four bytes of IFD specifies byte offset to next IFD. 
          % If this is zero, it means there's no more IFDs. 
          ifdPos = fread(fID, 1, 'uint32', byteOrder); 
          % IFD is structured as follows: 
          % ----- bytes 1-2: field tag        
          % ----- bytes 3-4: field type       
          % ----- bytes 5-8: length
          % ----- bytes 9-12: value/offset 
          for field = 1:numEntries
              fseek(fID, entryPos+12*(field-1), 'bof');
              IFD{ifdIndex}(1,field) = fread(fID, 1, 'uint16', byteOrder);
              IFD{ifdIndex}(2,field) = fread(fID, 1, 'uint16', byteOrder);
              IFD{ifdIndex}(3,field) = fread(fID, 1, 'uint32', byteOrder);
              IFD{ifdIndex}(4,field) = fread(fID, 1, 'uint32', byteOrder);
          end
    end

    % Reading LSMinfo
    LSMdata = readLsmHeaders(fID, IFD, byteOrder); 

    if any(strcmpi(varargin, 'InfoOnly'))
        % do nothing
    else

        nIms = length(LSMdata.tifStripByteCounts);
        LSMdata.Data = cell(nIms, 1);

        % check if this is a line scan
        if LSMdata.dimY == 1
            LSMdata.dimY = LSMdata.dimT;          
        end
        nPixels = LSMdata.dimX * LSMdata.dimY;
    
        % The meat of the work: Loop through each img offset and
        % reconstruct the original image
        for im = 1:nIms
            offset = LSMdata.tifStripOffsets(im);

            bitDepth = strcat('uint', num2str( LSMdata.bitDepth ));
            if LSMdata.compression > 1
               bitDepth = 'int8'; 
            end
            pixels = int16(zeros(nPixels, 1));
            base = 1;
            last = 0;
            byteArray = zeros(LSMdata.tifStripByteCounts(1), 1);
            imgBytesToRead = length(byteArray);

            fseek(fID, offset, 'bof');

            byteArray = int8(fread(fID, imgBytesToRead, bitDepth, byteOrder));

            % slow in native Matlab - call C++ MEX function for speed;
            byteArray = lzwDecompress(byteArray);

            pixelsRead = length(byteArray) / 2;
            pixelsRead = pixelsRead - mod(pixelsRead, LSMdata.dimX);
            pmax = base + pixelsRead;
            if pmax > nPixels
                pmax = nPixels;
            end

            j = 1;    
            for i = base:pmax
                pixels(i) = typecast([byteArray(j), byteArray(j+1)], 'int16');
                j = j + 2;
            end

            if LSMdata.predictor == 2 % using LZW with Differencing
                for i = base:pmax
                    pixels(i) = pixels(i) + last;
                    if mod(i-1, LSMdata.dimX) == LSMdata.dimX - 1
                        last = 0;
                    else
                        last = pixels(i);
                    end
                end
            end
            LSMdata.Data{im, 1} = reshape(pixels,[LSMdata.dimX, LSMdata.dimY]).';
        end

        fclose(fID);
    end

% read all relevant LSM header info
function info = readLsmHeaders(fID, IFD, byteOrder)

    % get image bit depth
    if IFD{1}(3, IFD{1}(1, :) == 258) == 1
        info.bitDepth = IFD{1}(4, IFD{1}(1, :) == 258);
    else
        fseek(fID, IFD{1}(4,IFD{1}(1, :) == 258),'bof');
        info.bitDepth = fread(fID, 1, 'uint16', byteOrder);
    end

    info.compression = IFD{1}(4, IFD{1}(1, :) == 259);

    if IFD{1}(3, IFD{1}(1, :) == 317) == 1
        info.predictor = IFD{1}(4, IFD{1}(1, :) == 317);
    else
        info.predictor = 0;
    end

    info.tifStripOffsets = getStripData(fID, IFD, 273, byteOrder);
    info.tifStripByteCounts = getStripData(fID, IFD, 279, byteOrder);

    offsetLSMinfo = IFD{1}(4, IFD{1}(1, :) == 34412) + 8;
    fseek(fID, offsetLSMinfo, 'bof');
        info.dimX = fread(fID, 1, 'uint32', byteOrder);
        info.dimY = fread(fID, 1, 'uint32', byteOrder);
        info.dimZ = fread(fID, 1, 'uint32', byteOrder);
        info.dimC = fread(fID, 1, 'uint32', byteOrder);
        info.dimT = fread(fID, 1, 'uint32', byteOrder);
        info.intensityDataType = fread(fID, 1, 'uint32', byteOrder);
        info.thumbnailX = fread(fID, 1, 'uint32', byteOrder);
        info.thumbnailY = fread(fID, 1, 'uint32', byteOrder);
        info.voxSizeX = fread(fID, 1, 'float64', byteOrder);
        info.voxSizeY = fread(fID, 1, 'float64', byteOrder);
        info.voxSizeZ = fread(fID, 1, 'float64', byteOrder);
        % skipping OriginX, OriginY, OriginZ (each 8 bytes long)
    fseek(fID, offsetLSMinfo + 80, 'bof');
        info.ScanType = fread(fID, 1, 'uint16', byteOrder);
    fseek(fID, offsetLSMinfo + 100, 'bof');
        info.OffsetChannelColours = fread(fID, 1, 'uint32', byteOrder);    
    fseek(fID, offsetLSMinfo + 104, 'bof');
        msInterval = fread(fID, 1, 'double', byteOrder) * 1000;
    fseek(fID, offsetLSMinfo + 112, 'bof');
        info.OffsetChannelDataTypes = fread(fID, 1, 'uint32', byteOrder);
    fseek(fID, offsetLSMinfo + 124, 'bof');
        info.OffsetTimeStamps = fread(fID, 1, 'uint32', byteOrder);

    if info.OffsetTimeStamps ~=0
        info.Timing = getTimeStamps(fID, info.OffsetTimeStamps, byteOrder);
        info.Timing.scanInterval = msInterval;
    else
        info.msInterval = msInterval;
    end

    if info.OffsetChannelDataTypes ~= 0
        info.ChannelDataTypeVals = getChannelDataTypes(fID,...
                                        info.OffsetChannelDataTypes,...
                                        info.dimC, byteOrder);  
    end

    if info.OffsetChannelColours ~= 0
        info.namesAndColours = getChannelNamesAndColours(fID,...
                                        info.OffsetChannelColours,...
                                        info.dimC, byteOrder);
    end

    
% get Strip data
function stripData = getStripData(fID, IFD, code, byteOrder)

    n = IFD{1}(3, IFD{1}(1, :) == code);
    if n == 1
        stripData = IFD{1}(4, IFD{1}(1, :) == code);
    else
        fseek(fID, IFD{1}(4, IFD{1}(1, :) == code), 'bof');
        stripData = zeros(2,1);
        for offs = 1:n
            stripData(offs) = fread(fID, 1, 'uint32', byteOrder);
        end
    end

% get channel data types
function dataTypeVals = getChannelDataTypes(fID, offset, nChannels, byteOrder)

    dataTypeVals = zeros(nChannels, 1);
    fseek(fID, offset, 'bof');

    for c = 1:nChannels
        dataTypeVals(c) = fread(fID, 1, 'uint32', byteOrder);
    end


% get channel names (as they appear in microscope software) and colour data
function namesAndColours = getChannelNamesAndColours(fID, offset, nChannels,...
                                            byteOrder)
    fseek(fID, offset, 'bof');
    namesAndColours.BlockSize = fread(fID, 1, 'uint32', byteOrder);
    namesAndColours.NumColours = fread(fID, 1, 'uint32', byteOrder);
    namesAndColours.NumNames = fread(fID, 1, 'uint32', byteOrder);
    namesAndColours.ColoursOffset = fread(fID, 1, 'uint32', byteOrder);
    namesAndColours.NamesOffset = fread(fID, 1, 'uint32', byteOrder);
    namesAndColours.Mono = fread(fID, 1, 'uint32', byteOrder);

    fseek(fID, offset + namesAndColours.NamesOffset, 'bof');

    namesAndColours.ChannelNames = cell(nChannels,1);

    for ch = 1:nChannels
        size = fread(fID, 1, 'uint32', byteOrder);
        namesAndColours.ChannelNames{ch} = readNameASCII(fID, size, byteOrder);
    end

    fseek(fID, namesAndColours.ColoursOffset + offset, 'bof');

    namesAndColours.Colours = zeros(namesAndColours.NumColours, 1);

    for ch = 1 : namesAndColours.NumColours
        namesAndColours.Colours(ch) = fread(fID, 1, 'uint32', byteOrder);
    end

% read ASCII characters comprising channel names and convert to string
function str = readNameASCII(fID, size, byteOrder)

    charCount = 0;
    addchar = true;

    while charCount < size
        in = fread(fID, 1, 'uint8', byteOrder);
        if in == -1
            break
        end

        if addchar
            if in ~= 0
                chars(charCount + 1) = in;
            else
                addchar = false;
            end
        end
        charCount = charCount + 1;
    end

    str = native2unicode(chars, 'US-ASCII');


% read Timestamp data if available
function tStampData = getTimeStamps(fID, position, byteOrder)

    tStampData = struct('scanInterval', [], 'size', [], 'nTimeStamps', [],...
            'Stamps', [], 'TimeStamps', []);

    fseek(fID, position, 'bof');

    tStampData.size = fread(fID, 1, 'uint32', byteOrder);
    tStampData.nTimeStamps = fread(fID, 1, 'uint32', byteOrder);
    tStampData.Stamps = fread(fID, tStampData.nTimeStamps, 'double', byteOrder);
    tStampData.TimeStamps = tStampData.Stamps - tStampData.Stamps(1);






