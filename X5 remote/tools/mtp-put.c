#include <libmtp.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
int main(int c,char**v){LIBMTP_Init();LIBMTP_mtpdevice_t*d=LIBMTP_Get_First_Device();if(!d)return 2;
LIBMTP_Get_Storage(d,0);LIBMTP_file_t*f=LIBMTP_new_file_t();f->filename=strdup(v[2]);{FILE*fp=fopen(v[1],"rb");fseek(fp,0,SEEK_END);f->filesize=ftell(fp);fclose(fp);}
f->filetype=LIBMTP_FILETYPE_UNKNOWN;f->parent_id=strtoul(v[3],0,10);f->storage_id=d->storage->id;
int r=LIBMTP_Send_File_From_File(d,v[1],f,NULL,NULL);printf("send=%d id=%u\n",r,f->item_id);
if(r)LIBMTP_Dump_Errorstack(d);LIBMTP_Release_Device(d);return r;}
