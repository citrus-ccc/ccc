import sys
import os
import zipfile
from xml.dom import minidom

def get_epub_info(fname):
    # epubファイルはzipファイル
    zip = zipfile.ZipFile(fname)

    # /META-INF/container.xml からメタデータが記録されているファイルのパスを取得する
    txt = zip.read('META-INF/container.xml')
    dom = minidom.parseString(txt)
    rootfile = dom.getElementsByTagNameNS('urn:oasis:names:tc:opendocument:xmlns:container', 'rootfile')[0]
    opf_path = rootfile.getAttribute('full-path')

    # OPFファイルのpackage要素の中のmetadata要素を取得する
    opf = zip.read(opf_path)
    dom = minidom.parseString(opf)
    metadata = dom.getElementsByTagNameNS('http://www.idpf.org/2007/opf', 'metadata')[0]

    # metadata要素の情報をディクショナリに整形する
    res = {}
    for s in ['title', 'language', 'creator', 'date', 'identifier']:
        elements = metadata.getElementsByTagNameNS('http://purl.org/dc/elements/1.1/', s)
        if elements:
            res[s] = elements[0].firstChild.data
    return res

def valid_file_name(file_name):
    # WIndowsのファイル名禁止文字
    file_name = file_name.replace('?', '？')
    file_name = file_name.replace('\\', '￥')
    file_name = file_name.replace('/', '／')
    file_name = file_name.replace('<', '＜')
    file_name = file_name.replace('>', '＞')
    file_name = file_name.replace('*', '＊')
    file_name = file_name.replace('\"', '”')
    file_name = file_name.replace('|', '｜')
    file_name = file_name.replace(':', '：')
    file_name = file_name.replace(';', '；')

    # Linuxのファイル名禁止文字
    file_name = file_name.replace('\0', '')

    # Macのファイル名禁止文字
    file_name = file_name.replace(',', '，')

    return file_name


def main():
    args = sys.argv
    work_path = args[1]

    epub_files = os.listdir(work_path)
    for index, epub_file in enumerate(epub_files):
        if epub_file.endswith(".epub"):
            epub_file_path = os.path.join(work_path, epub_file)
            book = get_epub_info(epub_file_path)
            title = valid_file_name(book['title']) + '.epub'
            print('rename epub [{0}/{1}] : {2} -> {3}'.format(index +
                                                              1, len(epub_files), epub_file, title))
            os.rename(epub_file_path, os.path.join(work_path, title))


if __name__ == "__main__":
    main()
