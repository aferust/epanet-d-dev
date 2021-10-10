/* EPANET 3
 *
 * Copyright (c) 2016 Open Water Analytics
 * Distributed under the MIT License (see the LICENSE file for details).
 *
 */
module epanet.utilities.mempool;

import core.stdc.stdlib: malloc, cfree = free;

//! \class MemPool
//! \brief A simple pooled memory allocator.

enum ALLOC_BLOCK_SIZE = 64000;       /*(62*1024)*/

struct MemBlock
{
    MemBlock *next;   /* Next Block          */
    char*     block,  /* Start of block      */
              free,   /* Next free in block  */
              end;    /* block + block size  */
}

class MemPool
{
    char* alloc(size_t size){
        /*
        **  Align to 4 byte boundary - should be ok for most machines.
        **  Change this if your machine has weird alignment requirements.
        */
        size = (size + 3) & 0xfffffffc;

        if (!current) return null;
        char* ptr = current.free;
        current.free += size;

        /* Check if the current block is exhausted. */

        if (current.free >= current.end)
        {
            /* Is the next block already allocated? */

            if (current.next)
            {
                /* re-use block */
                current.next.free = current.next.block;
                current = current.next;
            }
            else
            {
                /* extend the pool with a new block */
                current.next = createMemBlock();
                if (!current.next) return null;
                current = current.next;
            }

            /* set ptr to the first location in the next block */

            ptr = current.free;
            current.free += size;
        }

        /* Return pointer to allocated memory. */

        return ptr;
    }
    void reset(){
        current = first;
        current.free = current.block;
    }

    this(){
        first = createMemBlock();
        current = first;
    }

    ~this(){
        while (first)
        {
            current = first.next;
            deleteMemBlock(first);
            first = current;
        }
    }

  private:
    MemBlock* first;
    MemBlock* current;
}

static MemBlock* createMemBlock()
{
    MemBlock* memBlock = cast(MemBlock*)malloc(MemBlock.sizeof);
    if (memBlock)
    {
        memBlock.block = cast(char*)malloc(ALLOC_BLOCK_SIZE * char.sizeof);
        if (memBlock.block is null)
        {
            cfree(memBlock);
            return null;
        }
        memBlock.free = memBlock.block;
        memBlock.next = null;
        memBlock.end = memBlock.block + ALLOC_BLOCK_SIZE;
    }
    return memBlock;
}

static void deleteMemBlock(MemBlock* memBlock)
{
    cfree(memBlock.block);
    cfree(memBlock);
}