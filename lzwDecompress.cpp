#include "mex.hpp"
#include "mexAdapter.hpp"
#include "BitReader_C++\BitReader.cpp"
#include <vector>

using matlab::mex::ArgumentList;
using namespace matlab::data;

class MexFunction : public matlab::mex::Function {
    // Pointer to MATLAB engine to call fprintf
    std::shared_ptr<matlab::engine::MATLABEngine> matlabPtr = getEngine();
    
    ArrayFactory f;
    
public:
    void operator()(ArgumentList outputs, ArgumentList inputs) {
        
        TypedArray<int8_t> const in = std::move(inputs[0]);
        
        std::vector<int8_t> original = decompLZW(in);
        
        TypedArray<int8_t> out = f.createArray<int8_t>({1,original.size()});
        std::move(original.begin(), original.end(), out.begin());
        
        outputs[0] = out;
    }
    
    // decompress image compressed with Lempel-Zev Welch technique
    std::vector<int8_t> decompLZW(TypedArray<int8_t> const in) {
        
        // the return vector
        std::vector<int8_t> out;
        size_t inSize = in.getNumberOfElements(); // in-built matlab::data::Array member function
        if (in.isEmpty() || inSize == 0){
            out.push_back(-1);
            return out;
        }
        
        out.reserve(inSize);
        
        std::vector<std::vector<int8_t>> symbolTable(4096, std::vector<int8_t>(1));
		std::vector<int8_t> symbol;

		int bitsToRead = 9;
		int nextSymbol = 258;
		int code = 0;
		int oldCode = -1;
        bool initSymbol = false;
        
		// BitReader object to read arbitrary bit sequences from input array
		auto br = makeReader(in.begin(), in.end());

		while (out.size() < inSize) {
			code = br.readBits(bitsToRead);

			if (code == 257 || code == -1) break;

			if (code == 256) {
				// initialize first values of symbol table
				if (!initSymbol) 
				{
					// initialize first values of symbol table
					for (int i = 0; i < 256; i++) {
						symbolTable[i][0] = (int8_t)i;
					}
					initSymbol = true;
				}

				nextSymbol = 258;
				bitsToRead = 9;
				code = br.readBits(bitsToRead);

				if (code == 257 || code == -1) break;

				out.insert(out.end(), symbolTable[code].begin(), symbolTable[code].end());
				oldCode = code;
			}
			else {
				if (code < nextSymbol) {
					// code is already in the symbol table
					out.insert(out.end(), symbolTable[code].begin(), symbolTable[code].end());
					// add byte vector to symbol table
                    symbolTable[nextSymbol].assign(symbolTable[oldCode].begin(), symbolTable[oldCode].end());
                    symbolTable[nextSymbol].push_back(symbolTable[code][0]);
					
				}
				else {
					// code not in symbol table yet
                    symbolTable[nextSymbol].assign(symbolTable[oldCode].begin(), symbolTable[oldCode].end());
                    symbolTable[nextSymbol].push_back(symbolTable[oldCode][0]);
					out.insert(out.end(), symbolTable[nextSymbol].begin(), symbolTable[nextSymbol].end());
				}

				// reset buffer vector
				oldCode = code;
				nextSymbol++;

				if (nextSymbol == 511) {
					bitsToRead = 10;
				}
				else if (nextSymbol == 1023) {
					bitsToRead = 11;
				}
				else if (nextSymbol == 2047) {
					bitsToRead = 12;
				}
			}
		}
       
        return out;
    }
};




   

        


