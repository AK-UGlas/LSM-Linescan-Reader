classdef MatBitBuffer < handle
    
    properties (Access = private)
        currentByte
        currentBit
        buffer
        endOfByte
        endOfFlag
    end
    
    methods
        % Constructor
        function MBB = MatBitBuffer(buffer)
            MBB.currentByte = 1;
            MBB.currentBit = 0;
            MBB.buffer = buffer;
            MBB.endOfByte = length(buffer) + 1;
            MBB.endOfFlag = false;
        end
        
        function outVal = getBits(MBB, bitsToRead)
            
            if bitsToRead == 0
                outVal = 0;
                return
            elseif MBB.endOfFlag
                outVal = -1;
                return
            end
            
            bitArray = zeros(1, bitsToRead);
            startBit = 1;
            
            while ~bitsToRead == 0 && ~MBB.endOfFlag
                
                if bitsToRead >= 8 - MBB.currentBit
                % here we're reading from our current position until the end of the byte
                
                    if MBB.currentBit == 0
                        bitArray(startBit:startBit + 7) = bitget(MBB.buffer(MBB.currentByte), 8:-1:1);
                        startBit = startBit + 8;
                        bitsToRead = bitsToRead - 8;
                    else
                        thisRead = 8 - MBB.currentBit;
                        bitArray(startBit : startBit + thisRead-1) = bitget(MBB.buffer(MBB.currentByte), 8-MBB.currentBit:-1:1);
                        bitsToRead = bitsToRead - (8 - MBB.currentBit);
                        startBit = startBit + thisRead;
                        MBB.currentBit = 0;
                    end
                    
                    MBB.currentByte = MBB.currentByte + 1;
                    
                    % if we're at the last byte in the buffer, we're done
                    if MBB.currentByte == MBB.endOfByte
                        MBB.endOfFlag = true;
                        break
                    end
                    
                else
                    % here we're only reading a partial section of a byte.
                    % This is the endpoint of the call to getBits
                    bitArray(startBit : startBit + bitsToRead - 1) = bitget(MBB.buffer(MBB.currentByte), 8:-1:(8-(bitsToRead-1)));
                    MBB.currentBit = MBB.currentBit + bitsToRead;
                    bitsToRead = 0;
                end
                
                            
            end
            
            outVal = polyval(bitArray, 2);
        end
        
    end
end