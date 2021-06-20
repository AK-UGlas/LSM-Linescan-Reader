function data = lzwDecompressMatLab(inputByteArray, imgByteCount)
% lzwDecompressMatlab
% Pure Matlab implementation of lzw decompression for Tiff images.
% As LZW requires multiple iterations, Matlab optimization is difficult,
% and larger images (>50000000 pixels) are slow to open. Other speed tweaks
% have been used to compensate: using a procedural version of the
% readBits function instead of a cleaner Class implementation reduces
% processing time by 30-40%

if isempty(inputByteArray)
    data = inputByteArray;
    return 
end

symbolTable = cell(4096, 1);

bitsToRead = 9;
nextSymbol = 258;
oldCode = -1;
byteArraySize = length(inputByteArray);
out = zeros(byteArraySize, 1);
outSize = 0;

backMask = [0, 1, 3, 7, 15, 31, 63, 127];
frontMask = [0, 128, 192, 224, 240, 248, 252, 254];
bitParams = int32([byteArraySize + 1, 0, 1, 0]);
% counter for debugging
count = 0;

while outSize < imgByteCount
    [code, bitParams] = readBits(inputByteArray, bitsToRead, bitParams, backMask, frontMask);
    
    if code == 257 || code == -1
        break
    end
    
    if code == 256
        % initialise the symbol table
        for i = 0:255
            if i < 128
                symbolTable{i+1} = i;
            else
                symbolTable{i+1} = i-256;
            end
        end
        
        nextSymbol = 258;
        bitsToRead = 9;
        [code, bitParams] = readBits(inputByteArray, bitsToRead, bitParams, backMask, frontMask);
        
        if code == 257 || code == -1
            break
        end
        oldCode = code;
        symbolLength = length(symbolTable{code + 1});
        out(outSize + 1 : outSize + symbolLength) = symbolTable{code + 1};
        outSize = outSize + symbolLength;
    else
        if code < nextSymbol % code is already in the table
            symbolLength = length(symbolTable{code + 1});
            out(outSize + 1 : outSize + symbolLength) = symbolTable{code + 1};
            % add string to table
            toAdd = cat(1, symbolTable{oldCode+1}, symbolTable{code+1}(1));
            symbolTable{nextSymbol+1} = toAdd(1:length(toAdd));
        else % code is not in the table
            toAdd = cat(1, symbolTable{oldCode+1}, symbolTable{oldCode+1}(1));
            symbolTable{nextSymbol+1} = toAdd(1:length(toAdd));
            symbolLength = length(symbolTable{nextSymbol + 1});
            out(outSize + 1 : outSize + symbolLength) = symbolTable{nextSymbol + 1};
        end
        outSize = outSize + symbolLength;
        oldCode = code;
        nextSymbol = nextSymbol + 1;
        
        switch nextSymbol
            case 511
                bitsToRead = 10;
            case 1023
                bitsToRead = 11;
            case 2047
                bitsToRead = 12;
        end
    end
    count = count + 1;
end

data = int8(out(1:outSize));

% separate non-class function (faster than using BitReader class)
function [intToStore, params] = readBits(byteArray, bitsToRead, params, backMask, frontMask)

    if params(2)
        intToStore = -1;
        return
    end
    
    intToStore = 0;

    while ~bitsToRead == 0 && ~params(2)
                
        if bitsToRead >= 8 - params(4)
            % here we read until the end of byte   
            if params(4) == 0 % special case

                intToStore = bitshift(intToStore, 8);
                cb = int32(byteArray(params(3))); % cast is essential here
                if cb < 0
                    cb = cb + 256;
                end
                intToStore = intToStore + cb; 
                bitsToRead = bitsToRead - 8;

            else
                shift = 8 - params(4);
                intToStore = bitshift(intToStore, shift) + bitand(int32(byteArray(params(3))), int32(backMask(9 - params(4))));
                bitsToRead = bitsToRead - shift;
                params(4) = 0;
            end

            params(3) = params(3) + 1;

            if params(3) == params(1)
                params(2) = 1;
                return
            end

        else
            % here we're only reading part of a byte, but not to the end
            intToStore = bitshift(intToStore, bitsToRead);
            cb = int32(byteArray(params(3)));
            if cb < 0
                cb = cb + 256;
            end

            intToStore = intToStore + bitshift(bitand(cb, int32(0x00FF - frontMask(params(4) + 1))), -(8 - (params(4) + bitsToRead)));
            params(4) = params(4) + bitsToRead;
            bitsToRead = 0;
        end  
    end
    % end of while

















