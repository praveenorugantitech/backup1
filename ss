import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.nio.file.Paths;
import java.util.zip.ZipEntry;
import java.util.zip.ZipInputStream;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;

// Fetch the response
ResponseEntity<byte[]> response = restTemplate.exchange(url, HttpMethod.GET, requestEntity, byte[].class);

if (response.getStatusCode() == HttpStatus.OK && response.getBody() != null) {
    byte[] fileData = response.getBody();

    // Check if the content type is multipart with boundary information (optional, for debugging)
    String contentType = response.getHeaders().getContentType().toString();
    System.out.println("Content-Type: " + contentType);

    try (ByteArrayInputStream byteStream = new ByteArrayInputStream(fileData);
         ZipInputStream zipInputStream = new ZipInputStream(byteStream)) {

        ZipEntry zipEntry;
        while ((zipEntry = zipInputStream.getNextEntry()) != null) {
            String entryName = zipEntry.getName();
            System.out.println("Extracting entry: " + entryName);

            // Extract each file from the zip entry
            ByteArrayOutputStream bos = new ByteArrayOutputStream();
            byte[] buffer = new byte[1024];
            int len;
            while ((len = zipInputStream.read(buffer)) > 0) {
                bos.write(buffer, 0, len);
            }

            // Save each extracted file (optional - adjust folder path as needed)
            saveFile(bos.toByteArray(), entryName, folderPath);
            zipInputStream.closeEntry();
        }

    } catch (IOException e) {
        log.error("Error processing zip file content", e);
    }
} else {
    log.error("Failed to download the zip file.");
}
