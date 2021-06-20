classdef BitBuffer < handle
 %
 % A class for reading arbitrary numbers of bits from a byte array.
 % Original @author Eric Kjellman egkjellman at wisc.edu (Java, ImageJ)
 % 
 % Poor performance of Matlab bitwise operations necessitates casting. 
 % Results in increased overhead relative to Java version
 
    properties (Access = private)
        currentByte
        currentBit
        byteBuffer
        endOfByte
        backMask
        frontMask
        endOfFlag
    end
    
    methods
        % Constructor
        function BB = BitBuffer(byteBuffer)
            BB.currentByte = 1;
            BB.currentBit = int32(0);
            BB.byteBuffer = byteBuffer;
            BB.endOfByte = length(byteBuffer) + 1;
            BB.backMask = [0, 1, 3, 7, 15, 31, 63, 127];
            BB.frontMask = [0, 128, 192, 224, 240, 248, 252, 254];
            BB.endOfFlag = false;
        end
        
        function intToStore = getBits(BB, bitsToRead)
            
            if bitsToRead <= 0
                intToStore = 0;
                return
            elseif BB.endOfFlag
                intToStore = -1;
                return
            end
            
            intToStore = 0;
            
            while ~(bitsToRead == 0) && ~BB.endOfFlag
                
                if bitsToRead >= 8 - BB.currentBit
                    % here we read until the end of byte   
                    if BB.currentBit == 0 % special case
                        
                        intToStore = bitshift(intToStore, 8);
                        cb = int32(BB.byteBuffer(BB.currentByte));
                        if cb < 0
                            cb = cb + 256;
                        end
                        intToStore = intToStore + cb; 
                        bitsToRead = bitsToRead - 8;
                        
                    else
                        shift = 8 - BB.currentBit;
                        intToStore = bitshift(intToStore, shift);
                        andResult = bitand(int32(BB.byteBuffer(BB.currentByte)), int32(BB.backMask(9 - BB.currentBit)));
                        intToStore = intToStore + andResult;
                        bitsToRead = bitsToRead - shift;
                        BB.currentBit = 0;
                    end
                   
                    BB.currentByte = BB.currentByte + 1;
                    
                    if BB.currentByte == BB.endOfByte
                        BB.endOfFlag = true;
                        return
                    end
                    
                else
                    % here we're only reading part of a byte, and not all
                    % the way to the end
                    intToStore = bitshift(intToStore, bitsToRead);
                    cb = int32(BB.byteBuffer(BB.currentByte));
                    if cb < 0
                        cb = cb + 256;
                    end
                    
                    shift = -(8 - (BB.currentBit + bitsToRead));
                    cb = bitand(cb, int32(( 0x00FF - BB.frontMask(BB.currentBit + 1) )));
                    bsResult = bitshift(cb, shift);
                    intToStore = intToStore + bsResult;
                    BB.currentBit = BB.currentBit + bitsToRead;
                    bitsToRead = 0;
                end  
            end
            % end of while
            return
        end
        % end of getBits  
    end
    % end of methods
end
























