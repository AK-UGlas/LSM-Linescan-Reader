// BitReader.cpp 
// Function to read arbitrary numbers of bits from a byte array
// Designed to be called from Matlab as native functions are slow 
// on large (>100000 elements) arrays
// C++ port of the BitBuffer class written by @author Eric Kjellman 
// egkjellman at wisc.edu (Java, ImageJ)

template<typename Iter> class BitReader
{
	Iter currentByte, lastByte;
	int currentBit = 0;
	bool eofFlag = false;
	int backMask[8] = { 0x0000, 0x0001, 0x0003, 0x0007,
			0x000F, 0x001F, 0x003F, 0x007F };
	int frontMask[8] = { 0x0000, 0x0080, 0x00C0, 0x00E0,
			0x00F0, 0x00F8, 0x00FC, 0x00FE };

public:
    // constructor
	BitReader(Iter first, Iter last) : currentByte(first), lastByte(last) {}
    
    // read arbitrary number of bits using iterators into current array
	int readBits(int bitsToRead) {
		if (bitsToRead == 0) {
			return 0;
		}
		else if (eofFlag) {
			return -1;
		}

		int toStore = 0;
		while (bitsToRead != 0 && !eofFlag) {

			if (bitsToRead >= 8 - currentBit) {

				// read from current bit to end of current byte

				if (currentBit == 0) {
					toStore = toStore << 8;
					int cb = (int)(*currentByte);
					toStore += cb < 0 ? 256 + cb : cb;
					bitsToRead -= 8;
				}
				else {
					toStore = toStore << (8 - currentBit);
					toStore += *currentByte & backMask[8 - currentBit];
					bitsToRead -= (8 - currentBit);
					currentBit = 0;
				}

				currentByte++;
				// can check if we've reached the end of the byte array here  
				// as we'll always be at the beginning of a new byte
				if (currentByte == lastByte) {
					eofFlag = true;
					return toStore;
				}
			}
			else {
				// read part of a byte but not to the end
				toStore = toStore << bitsToRead;
				int cb = (int)(*currentByte);
				cb = (cb < 0 ? 256 + cb : cb);
				toStore += (cb & (0x00FF - frontMask[currentBit])) >> (8 - (currentBit + bitsToRead));
				currentBit += bitsToRead;
				bitsToRead = 0;
			}
		}
		return toStore;
	};
};

// helper function to create instance of class based on any iterator type 
// (see lzwDecompress.cpp for example of usage) 
template <typename Iter>
BitReader<Iter> makeReader(Iter first, Iter last) {
	return BitReader<Iter>(first, last);
}



