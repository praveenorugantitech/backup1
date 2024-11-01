import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.client.RestTemplate;

import java.io.*;
import java.nio.file.Files;
import java.nio.file.Paths;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.zip.ZipEntry;
import java.util.zip.ZipInputStream;

public class ZipFileFetcher {

    private final RestTemplate restTemplate;

    public ZipFileFetcher(RestTemplate restTemplate) {
        this.restTemplate = restTemplate;
    }

    public String fetchAndSaveZipFile(String url, String folderPath) {
        try {
            ResponseEntity<byte[]> response = restTemplate.getForEntity(url, byte[].class);

            // Log status and headers
            if (response.getStatusCode() == HttpStatus.OK) {
                System.out.println("Response Headers: " + response.getHeaders());
                System.out.println("Content-Type: " + response.getHeaders().getContentType());

                byte[] fileData = response.getBody();
                if (fileData != null) {
                    // Save the byte array as a zip file for debugging
                    String tempZipFilePath = folderPath + "/temp_download.zip";
                    Files.write(Paths.get(tempZipFilePath), fileData);

                    // Try to unzip the downloaded file
                    return extractZipFile(fileData, folderPath);
                } else {
                    System.out.println("Error: File data is null");
                }
            } else {
                System.out.println("Failed to download file. Status: " + response.getStatusCode());
            }
        } catch (Exception e) {
            e.printStackTrace();
            System.out.println("Error occurred while fetching or processing the zip file: " + e.getMessage());
        }
        return null;
    }

    private String extractZipFile(byte[] fileData, String folderPath) {
        try (ZipInputStream zipInputStream = new ZipInputStream(new ByteArrayInputStream(fileData))) {
            ZipEntry zipEntry;
            while ((zipEntry = zipInputStream.getNextEntry()) != null) {
                String fileName = zipEntry.getName();
                System.out.println("Extracting file: " + fileName);

                // Set up file output path
                File outputFile = new File(folderPath, fileName);
                try (FileOutputStream fos = new FileOutputStream(outputFile)) {
                    byte[] buffer = new byte[1024];
                    int len;
                    while ((len = zipInputStream.read(buffer)) > 0) {
                        fos.write(buffer, 0, len);
                    }
                }
                zipInputStream.closeEntry();
                System.out.println("File extracted to: " + outputFile.getAbsolutePath());
            }
            return "Extraction completed.";
        } catch (IOException e) {
            e.printStackTrace();
            System.out.println("Error occurred while extracting zip file: " + e.getMessage());
            return null;
        }
    }

    public static void main(String[] args) {
        RestTemplate restTemplate = new RestTemplate();
        ZipFileFetcher fetcher = new ZipFileFetcher(restTemplate);
        String folderPath = "your/folder/path";  // replace with your desired path
        String url = "http://your-url.com/file.zip";  // replace with your actual URL
        fetcher.fetchAndSaveZipFile(url, folderPath);
    }
}
