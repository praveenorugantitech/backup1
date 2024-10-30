package com.ford.gpcse.service.impl;

import com.ford.gpcse.bo.*;
import com.ford.gpcse.common.Constants;
import com.ford.gpcse.dto.*;
import com.ford.gpcse.entity.*;
import com.ford.gpcse.exception.ProgramSearchLimitExceedException;
import com.ford.gpcse.exception.ResourceNotFoundException;
import com.ford.gpcse.repository.*;
import com.ford.gpcse.service.SearchDataService;
import com.ford.gpcse.util.DateFormatterUtility;
import com.ford.gpcse.util.NoticeFormatterUtility;
import jakarta.persistence.criteria.*;
import lombok.RequiredArgsConstructor;
import org.apache.commons.lang3.StringUtils;
import org.springframework.data.jpa.domain.Specification;
import org.springframework.stereotype.Service;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.LocalTime;
import java.time.format.DateTimeFormatter;
import java.util.*;
import java.util.stream.Collectors;

@Service
@RequiredArgsConstructor
public class SearchDataServiceImpl implements SearchDataService {

    private final PartRepository partRepository;
    private final ReleaseRequestRepository releaseRequestRepository;
    private final PartFirmwareRepository partFirmwareRepository;
    private final ProgramDescriptionRepository programDescriptionRepository;
    private final ProgramPartRepository programPartRepository;
    private final SignoffRepository signoffRepository;
    private final FirmwareRepository firmwareRepository;

    private static final String NO_PARTS_FOUND = "No Parts to display";

    @Override
    public List<FirmwareResponse> fetchFirmwareDetailsByWersConcern(String wersConcern) {
        List<FirmwareDto> firmwareDtos = partRepository.fetchFirmwareDetailsByWersConcern(wersConcern);
        if (firmwareDtos.isEmpty()) {
            throw new ResourceNotFoundException("No Release was found. Please try again.");
        }
        return convertToFirmwareResponse(firmwareDtos);
    }

    @Override
    public List<FirmwareResponse> fetchFirmwareDetailsByWersNotice(String wersNotice) {
        List<FirmwareDto> firmwareDtos = partRepository.fetchFirmwareDetailsByWersNotice(NoticeFormatterUtility.formatWersNotice(wersNotice));
        if (firmwareDtos.isEmpty()) {
            throw new ResourceNotFoundException("No Release was found.  Please try again.");
        }
        return convertToFirmwareResponse(firmwareDtos);
    }

    @Override
    public List<FirmwareResponse> fetchFirmwareDetailsByPrograms(List<Long> programKeys) {
        if (programKeys.size() >= 10) {
            throw new ProgramSearchLimitExceedException("Please select less than 10 programs.");
        }
        List<FirmwareDto> firmwareDtos = partRepository.fetchFirmwareDetailsByPrograms(programKeys);
        if (firmwareDtos.isEmpty()) {
            throw new ResourceNotFoundException("No Programs");
        }
        return convertToFirmwareResponse(firmwareDtos);
    }


    @Override
    public List<PartNumberSearchResponse> fetchFirmwareDetailsByPartNumber(PartNumberSearchRequest partNumberSearchRequest) {
        // Create a specification based on the search request
        Specification<Part> spec = byCriteriaForPartNumber(partNumberSearchRequest);

        // Count total records matching the specification
        long totalRecords = partRepository.count(spec);

        // If total records exceed 498, throw an error
        if (totalRecords > 498) {
            throw new RuntimeException("Too many results. Please refine your search.");
        }

        // Fetch the results using the same specification
        List<Part> parts = partRepository.findAll(spec);

        if (parts.isEmpty()) {
            throw new ResourceNotFoundException(NO_PARTS_FOUND);
        }

        // Group parts by concern number
        Map<String, List<PartDetail>> groupedByConcernNumber = parts.stream()
                .map(part -> new PartDetail(
                        part.getPartR(),
                        part.getHardwarePartR(),
                        part.getSupplier().getSuplX(),
                        part.getCatchWordC(),
                        part.getCalibR(),
                        part.getStatC(),
                        DateFormatterUtility.dateTimeStringConcern(part.getConcernY()),
                        part.getReleaseType().getRelTypC(),
                        part.getReleaseUsage().getRelUsgC(),
                        part.getCmtX(),
                        part.getConcernC(),
                        part.getSwDlSpecR(),
                        part.getProcCmtX(),
                        part.getBldLvlC(),
                        part.getPrtyC(),
                        part.getPrtyDtlX()
                ))
                .collect(Collectors.groupingBy(PartDetail::getConcernNumber));

        // Map results to PartNumberSearchResponse
        return groupedByConcernNumber.entrySet().stream()
                .map(entry -> new PartNumberSearchResponse(
                        entry.getKey(),
                        entry.getValue()
                ))
                .limit(499) // Limit to 499
                .collect(Collectors.toList());
    }

    @Override
    public String fetchWersTextByConcern(String wersConcern) {
        // Fetch Part Numbers based on Wers Concern
        List<String> partNumbers = partRepository.fetchPartNumbersBasedOnConcern(wersConcern);

        if (partNumbers.isEmpty()) {
            throw new ResourceNotFoundException(NO_PARTS_FOUND);
        }

        List<Object[]> partsData = partRepository.fetchParts(partNumbers);
        Map<String, String> partProgramsMap = new HashMap<>();
        List<ProgramPart> programParts = programPartRepository.findByPart_PartRIn(partNumbers);
        for (ProgramPart programPart : programParts) {
            partProgramsMap.compute(programPart.getPart().getPartR(),
                    (key, existing) -> (existing == null ? "" : existing + ", ") + programPart.getPgmK());
        }
        List<WersTextPartDto> wersTextPartDtos = new ArrayList<>();
        for (Object[] partData : partsData) {
            String partR = (String) partData[0];
            String relTypeC = (String) partData[1];
            String backwardCompatC = (String) partData[2];
            String hardwarePartR = (String) partData[3];
            String releaseUsageC = (String) partData[4];

            // Get the programs from the map, default to an empty string if none found
            String programs = partProgramsMap.getOrDefault(partR, "");

            wersTextPartDtos.add(new WersTextPartDto(partR, relTypeC, backwardCompatC, hardwarePartR, releaseUsageC, programs));
        }

        List<WersTextPartDescriptionDto> wersTextPartDescriptionDtos = programDescriptionRepository.fetchPartsWithProgramDescription(partNumbers);
        List<WersTextPartCalibDto> wersTextPartCalibDtos = partRepository.fetchPartsWithCalib(partNumbers);

        StringBuilder strText = new StringBuilder();

        for (WersTextPartDto partDto : wersTextPartDtos) {
            // Append programs
            String programs = partDto.getPrograms();
            if (programs != null && !programs.isEmpty()) {
                strText.append(programs).append("<br>");
            }

            // Build display values
            strText.append(wordWrap(getDisplayValue(partDto.getRelTypeC()) + " - " + getDisplayValue(partDto.getReleaseUsageC()), 79, " ", "<br>")).append("<br>");
            strText.append(wordWrap(getDisplayValue(partDto.getBackwardCompatC()), 79, " ", "<br>")).append("<br>");
            strText.append("HARDWARE: ").append(partDto.getHardwarePartR()).append("<br>");
            strText.append("RELATED MODULES:<br>");

            // Call to create table from descriptions
            strText.append(wersTable(wersTextPartDescriptionDtos, partDto.getRelTypeC())).append("<br>");
        }

        // Add lineage table
        strText.append(generateLineageTable(wersTextPartCalibDtos)).append("<br>");

        return strText.toString();
    }

    @Override
    public ReleaseStatusConcernResponse fetchReleaseStatusDetailsByWersConcern(String wersConcern) {
        ReleaseStatusConcernDto releaseStatusConcernDto = partRepository.fetchReleaseStatusDetailsByWersConcern(wersConcern);

        if (releaseStatusConcernDto == null) {
            throw new ResourceNotFoundException("No Records was found.");

        }

        return new ReleaseStatusConcernResponse(
                releaseStatusConcernDto.getPartR(),
                releaseStatusConcernDto.getCalibR(),
                releaseStatusConcernDto.getEngineerCdsidC(),
                releaseStatusConcernDto.getHardwarePartR(),
                releaseStatusConcernDto.getCoreHardwarePartR(),
                releaseStatusConcernDto.getMicroTypX(),
                releaseStatusConcernDto.getStratCalibPartR(),
                releaseStatusConcernDto.getStratRelC(),
                programDescriptionRepository.fetchProgramDescriptionByPartNumber(releaseStatusConcernDto.getPartR()),
                releaseStatusConcernDto.getPartNumX(),
                new ReleaseStatusDetails(getStatusDescription(releaseStatusConcernDto.getStatC()), getStatusValue(releaseStatusConcernDto))
        );
    }

    public String getStatusValue(ReleaseStatusConcernDto releaseStatusConcernDto) {
        return switch (releaseStatusConcernDto.getStatC()) {
            case "PeadEdit" -> "<li>Waiting for Edit Module Base.</li>";
            case "PeadComplete" -> fetchPeadCompleteStatusValue(releaseStatusConcernDto.getPartR());
            case "FirmwareEdit" ->
                    fetchFirmwareEditStatusValue(releaseStatusConcernDto.getPartR(), releaseStatusConcernDto.getSuplC(), releaseStatusConcernDto.getRelTypC(), releaseStatusConcernDto.getStratRelC());
            case "SoftLock" ->
                    fetchSoftLockStatusValue(releaseStatusConcernDto.getPartR(), releaseStatusConcernDto.getSuplC());
            case "HardLock" ->
                    fetchHardLockStatusValue(releaseStatusConcernDto.getPartR(), releaseStatusConcernDto.getSuplC());
            default -> "";
        };

    }

    private String fetchHardLockStatusValue(String partR, String suplC) {
        String signoffProcessText = signoffProcess(partR, "Waiting for Hard Lock Process", Arrays.asList("VBFUL", "DCUUL", "P2LOC", "SWWER", "SWBLD", "PRDWL", "PRBLD", "SWAPR", "SWDRW", "SRPUL", "IVSSB", "IVSAB", "TELGR", "IVSSA", "IVSAA", "EOLPT", "EOLVO"), suplC);
        if (signoffProcessText.isEmpty()) {
            return "<li>Waiting for other parts to complete.</li>";
        } else {
            return signoffProcessText;
        }
    }

    private String fetchSoftLockStatusValue(String partR, String suplC) {
        String signoffProcessText = signoffProcess(partR, "Waiting for Review Process", Arrays.asList("SUPPR", "PEERR", "PEERA", "HWPER", "IVSEM"), suplC);
        if (signoffProcessText.isEmpty()) {
            return "<li>Waiting for Hard Lock.</li>";
        } else {
            return signoffProcessText;
        }
    }

    private String signoffProcess(String partR, String displayText, List<String> signOffTypes, String suplC) {
        List<Object[]> signoffDetails = signoffRepository.findSignoffDetails(partR, signOffTypes);
        if (signoffDetails.isEmpty()) {
            return "";
        } else {
            StringBuilder strHtm = new StringBuilder();
            strHtm.append("<li>");
            strHtm.append(displayText);
            strHtm.append("<ul>");
            for (Object[] detail : signoffDetails) {
                String signoffTypeX = detail[0] != null ? detail[0].toString() : "";
                String signoffTypeC = detail[1] != null ? detail[1].toString() : "";
                String runTimeInMin = detail[2] != null ? detail[2].toString() : "";
                // Check if the signoff type contains "Automation"
                if (signoffTypeX.toLowerCase().contains("automation")) {
                    // Generate HTML without link for automation signoffs
                    strHtm.append("<li>").append(signoffTypeX).append("</li>\n");
                    strHtm.append("<li>Running for ").append(runTimeInMin).append(" minutes</li>\n");
                } else {
                    // Generate HTML with a clickable link for other signoffs
                    strHtm.append("<li><a href=\"#\" onclick=\"OpenSignoffLookupForm('")
                            .append(partR).append("','").append(signoffTypeC).append("','")
                            .append(suplC).append("'); return false;\">")
                            .append(signoffTypeX).append("</a></li>\n");
                }
            }
            strHtm.append("</ul></li>");
            return strHtm.toString();


        }
    }


    private String fetchFirmwareEditStatusValue(String partR, String suplC, String relTypC, String stratRelC) {
        StringBuilder strHtm = new StringBuilder();
        fetchFirmwareHtm(partR, suplC, strHtm);
        strHtm.append(signoffProcess(partR, "Waiting for Calibration Review", Arrays.asList("CALUP", "CLSUP", "CLOBD", "SUDEP", "CLDEP", "PCDEP", "SUDEV", "CLDEV", "PCDEV"), suplC));
        strHtm.append(signoffProcess(partR, "Waiting for WERS Peer Review", Arrays.asList("PEERW"), suplC));

        if (strHtm.isEmpty()) {
            if (relTypC.equals("AFD") || relTypC.equals("AREUL") || relTypC.equals("PSUPR") || relTypC.equals("RC") || relTypC.equals("PROT") || stratRelC.isEmpty() || stratRelC.length() > 5) {
                Long countByPartRHasReviewSignOff = partFirmwareRepository.countByPartRHasReviewSignOff(partR);
                if (countByPartRHasReviewSignOff > 0) {
                    return "<li>Waiting to Send for Soft Lock.</li>";
                } else {
                    return "<li>Waiting to Send for Hard Lock.</li>";
                }
            } else {
                return "<li>Waiting for CFX Release or CART Sign-off.</li>";
            }
        } else {
            return strHtm.toString();
        }
    }

    private void fetchFirmwareHtm(String partR, String suplC, StringBuilder strHtm) {

        List<Object[]> firmwareDetails = firmwareRepository.findFirmwareDetails(partR);

        // Check if the result set is empty (equivalent to rsMySub.RecordCount = 0)
        if (firmwareDetails.isEmpty()) {
            strHtm.setLength(0); // Clear strHtm if no records are found
        } else {
            // Start building the HTML for firmware list
            strHtm.append("<li>Waiting for Firmware");
            strHtm.append("<ul>");

            // Loop through the firmware details (equivalent to do until rsMySub.EOF)
            for (Object[] detail : firmwareDetails) {
                String firmwareK = detail[1] != null ? detail[1].toString() : "";
                String firmwareN = detail[0] != null ? detail[0].toString() : "";

                // Append each firmware as a clickable link
                strHtm.append("<li><a href=\"#\" onclick=\"OpenFirmwareLookupForm('")
                        .append(partR).append("','").append(firmwareK).append("','")
                        .append(suplC).append("'); return false;\">")
                        .append(firmwareN).append("</a></li>");
            }

            // Close the unordered list and list item
            strHtm.append("</ul></li>");
        }
    }

    private String fetchPeadCompleteStatusValue(String partR) {
        // Has Firmware Item
        Long countByPartR = partFirmwareRepository.countByPartR(partR);
        Long countByPartRHasReviewSignOff = partFirmwareRepository.countByPartRHasReviewSignOff(partR);
        if (countByPartR > 0) {
            return "<li>Waiting to send for Firmware.</li>";
        } else if (countByPartRHasReviewSignOff > 0) {
            return "<li>Waiting to send for Soft Lock.</li>";
        } else {
            return "<li>Waiting to send for Hard Lock.</li>";
        }
    }

    public static String getStatusDescription(String statC) {
        return switch (statC) {
            case "" -> "";
            case "NewPnRequest" -> "New Part Number Request";
            case "PeadEdit", "PeadComplete" -> "Module Base Info Edit";
            case "FirmwareEdit" -> "Firmware Edit";
            case "SoftLock" -> "Soft Lock";
            case "HardLock" -> "Hard Lock";
            case "Complete" -> "Release Complete";
            default -> statC;
        };
    }


    @Override
    public List<ProductionPartNumberSearchResponse> fetchProductionPartNumber(ProductionPartNumberSearchRequest productionPartNumberSearchRequest) {
        List<Part> parts = partRepository.findAll(buildfindProductionPartNumberSpecification(productionPartNumberSearchRequest));
        if (parts.isEmpty()) {
            throw new ResourceNotFoundException(NO_PARTS_FOUND);
        }
        return parts.stream().map(part -> new ProductionPartNumberSearchResponse(part.getPartR(), part.getCatchWordC(), part.getCalibR(), part.getStratCalibPartR(), part.getHardwarePartR(), part.getMicroType().getMicroTypX(), part.getWersNtcR())).toList();
    }


    @Override
    public List<ReleaseRequestOutput> fetchReleaseRequests(ReleaseRequestSearchInput releaseRequestSearchInput) {
        Specification<ReleaseRequest> spec = findByCriteriaForReleaseRequests(releaseRequestSearchInput);
        List<ReleaseRequest> releaseRequests = releaseRequestRepository.findAll(spec);

        if (releaseRequests.isEmpty()) {
            throw new ResourceNotFoundException("No Release Requests");
        }
        return releaseRequests.stream().map(releaseRequest -> new ReleaseRequestOutput(releaseRequest.getRelReqK(), releaseRequest.getModuleType().getModuleTypC(), releaseRequest.getCalRLevelR(), releaseRequest.getProgramReleaseRequests() != null && !releaseRequest.getProgramReleaseRequests().isEmpty() ? releaseRequest.getProgramReleaseRequests().get(0).getProgramDescription().getMdlYrR() : null, releaseRequest.getProgramReleaseRequests() != null && !releaseRequest.getProgramReleaseRequests().isEmpty() ? releaseRequest.getProgramReleaseRequests().get(0).getProgramDescription().getPgmN() : null, releaseRequest.getProgramReleaseRequests() != null && !releaseRequest.getProgramReleaseRequests().isEmpty() ? releaseRequest.getProgramReleaseRequests().get(0).getProgramDescription().getEngN() : null, releaseRequest.getStatusC(), releaseRequest.getCreateS().format(DateTimeFormatter.ofPattern("MMM dd, yyyy")), releaseRequest.getCreateUserC())).toList();
    }

    private Specification<Part> buildfindProductionPartNumberSpecification(ProductionPartNumberSearchRequest productionPartNumberSearchRequest) {
        return (root, query, cb) -> {
            Predicate predicate = cb.conjunction();

            // Filter by Part Number
            if (productionPartNumberSearchRequest.getPartNumber() != null && !productionPartNumberSearchRequest.getPartNumber().isEmpty()) {
                String partNum = productionPartNumberSearchRequest.getPartNumber().toUpperCase();
                predicate = cb.and(predicate, cb.like(cb.upper(root.get(Constants.PART_R)), "%" + partNum + "%"));
            }

            // Filter by Software Part Number
            if (productionPartNumberSearchRequest.getSoftwarePartNumber() != null && !productionPartNumberSearchRequest.getSoftwarePartNumber().isEmpty()) {
                String swPartNum = productionPartNumberSearchRequest.getSoftwarePartNumber().toUpperCase();
                predicate = cb.and(predicate, cb.like(cb.upper(root.get("stratCalibPartR")), "%" + swPartNum + "%"));
            }

            // Filter by Catchword
            if (productionPartNumberSearchRequest.getCatchWord() != null && !productionPartNumberSearchRequest.getCatchWord().isEmpty()) {
                String catchWord = productionPartNumberSearchRequest.getCatchWord().toUpperCase();
                predicate = cb.and(predicate, cb.like(cb.upper(root.get("catchWordC")), "%" + catchWord + "%"));
            }

            // Filter by Calibration Number
            if (productionPartNumberSearchRequest.getCalibrationNumber() != null && !productionPartNumberSearchRequest.getCalibrationNumber().isEmpty()) {
                String calibrationNum = productionPartNumberSearchRequest.getCalibrationNumber().toUpperCase();
                predicate = cb.and(predicate, cb.like(cb.upper(root.get("calibR")), "%" + calibrationNum + "%"));
            }

            // Filter by Notice Number
            if (productionPartNumberSearchRequest.getWersNotice() != null && !productionPartNumberSearchRequest.getWersNotice().isEmpty()) {
                String noticeNumber = productionPartNumberSearchRequest.getWersNotice().toUpperCase();
                predicate = cb.and(predicate, cb.like(cb.upper(root.get("wersNtcR")), "%" + noticeNumber + "%"));
            }

            // Filter by Maintenance Strategy
            if (productionPartNumberSearchRequest.getStratRelName() != null && !productionPartNumberSearchRequest.getStratRelName().isEmpty()) {
                String stratRelName = productionPartNumberSearchRequest.getStratRelName().toUpperCase();
                predicate = cb.and(predicate, cb.like(cb.upper(root.get("stratRelC")), "%" + stratRelName + "%"));
            }

            // Filter by Chip ID
            if (productionPartNumberSearchRequest.getChipId() != null && !productionPartNumberSearchRequest.getChipId().isEmpty()) {
                String chipID = productionPartNumberSearchRequest.getChipId().toUpperCase();
                predicate = cb.and(predicate, cb.like(cb.upper(root.get("chipD")), "%" + chipID + "%"));
            }

            // Additional static filters
            predicate = cb.and(predicate,
                    cb.equal(root.get("archF"), "N"),
                    cb.isNotNull(root.get("moduleType")),
                    cb.isNotNull(root.get("releaseType"))
            );


            return predicate;
        };
    }


    private Specification<Part> byCriteriaForPartNumber(PartNumberSearchRequest request) {
        return (Root<Part> root, CriteriaQuery<?> query, CriteriaBuilder cb) -> {
            Predicate predicate = cb.conjunction();

            // Basic filters
            predicate = cb.and(predicate, cb.equal(root.get("archF"), "N"));
            predicate = cb.and(predicate, cb.notEqual(root.get("statC"), "NewPnRequest"));

            Join<Part, ReleaseType> releaseTypeJoin = root.join("releaseType", JoinType.INNER);
            // Conditional filters
            predicate = addPredicate(predicate, cb, releaseTypeJoin.get("relTypX").in(request.getReleaseTypes()),
                    request.getReleaseTypes() != null && !request.getReleaseTypes().isEmpty() && !request.getReleaseTypes().contains("All"));

            Join<Part, ModuleType> moduleTypeJoin = root.join("moduleType", JoinType.INNER);

            predicate = addPredicate(predicate, cb, cb.equal(moduleTypeJoin.get("moduleTypC"), request.getModuleType()),
                    request.getModuleType() != null && !request.getModuleType().isEmpty());

            Join<Part, RelUsg> releaseUsageJoin = root.join("releaseUsage", JoinType.INNER);

            predicate = addPredicate(predicate, cb, cb.equal(releaseUsageJoin.get("relUsgX"), request.getReleaseUsage()),
                    request.getReleaseUsage() != null && !request.getReleaseUsage().isEmpty() && !request.getReleaseUsage().equals("All"));

            predicate = addPredicate(predicate, cb, cb.like(root.get(Constants.PART_R), "%" + request.getAssemblyPN() + "%"),
                    request.getAssemblyPN() != null && !request.getAssemblyPN().isEmpty());

            predicate = addPredicate(predicate, cb, cb.like(root.get("hardwarePartR"), "%" + request.getHardwarePN() + "%"),
                    request.getHardwarePN() != null && !request.getHardwarePN().isEmpty());

            predicate = addPredicate(predicate, cb, cb.like(root.get("swDlSpecR"), "%" + request.getSoftwarePN() + "%"),
                    request.getSoftwarePN() != null && !request.getSoftwarePN().isEmpty());

            predicate = addPredicate(predicate, cb, cb.equal(root.get("engineerCdsidC"), request.getAppEng()), request.getAppEng() != null && !request.getAppEng().isEmpty());

            predicate = addPredicate(predicate, cb, cb.like(root.get("catchWordC"), "%" + request.getCatchWord() + "%"),
                    request.getCatchWord() != null && !request.getCatchWord().isEmpty());

            predicate = addPredicate(predicate, cb, cb.equal(root.get("calibR"), request.getCalibrationNum()),
                    request.getCalibrationNum() != null && !request.getCalibrationNum().isEmpty());

            predicate = addPredicate(predicate, cb, cb.equal(root.get("stratRelC"), request.getMainStrategy()),
                    request.getMainStrategy() != null && !request.getMainStrategy().isEmpty());

            predicate = addPredicate(predicate, cb, cb.equal(root.get("concernC"), request.getConcernNumber()),
                    request.getConcernNumber() != null && !request.getConcernNumber().isEmpty());

            // Date filters
            if (request.getCreatedDateFrom() != null && !request.getCreatedDateFrom().isEmpty()) {
                LocalDateTime createdDateFrom = LocalDateTime.of(LocalDate.parse(request.getCreatedDateFrom()), LocalTime.MIN);
                predicate = cb.and(predicate, cb.greaterThanOrEqualTo(root.get("createS"), createdDateFrom));
            }

            if (request.getCreatedDateTo() != null && !request.getCreatedDateTo().isEmpty()) {
                LocalDateTime createdDateTo = LocalDateTime.of(LocalDate.parse(request.getCreatedDateTo()), LocalTime.MAX);
                predicate = cb.and(predicate, cb.lessThanOrEqualTo(root.get("createS"), createdDateTo));
            }

            if (request.getReleasedDateFrom() != null && !request.getReleasedDateFrom().isEmpty()) {
                predicate = cb.and(predicate, cb.greaterThanOrEqualTo(root.get("reldY"), LocalDate.parse(request.getReleasedDateFrom())));
            }

            if (request.getReleasedDateTo() != null && !request.getReleasedDateTo().isEmpty()) {
                predicate = cb.and(predicate, cb.lessThanOrEqualTo(root.get("reldY"), LocalDate.parse(request.getReleasedDateTo())));
            }

            // Set ordering
            if (query != null) {
                query.orderBy(cb.asc(root.get("concernC")), cb.asc(root.get(Constants.PART_R)));
            }

            return predicate;
        };
    }

    // Helper method to add predicate only if the condition is met
    private Predicate addPredicate(Predicate predicate, CriteriaBuilder cb, Predicate condition, boolean applyCondition) {
        return applyCondition ? cb.and(predicate, condition) : predicate;
    }

    private Specification<ReleaseRequest> findByCriteriaForReleaseRequests(ReleaseRequestSearchInput releaseRequestSearchInput) {
        return (Root<ReleaseRequest> root, CriteriaQuery<?> query, CriteriaBuilder criteriaBuilder) -> {
            Predicate predicate = criteriaBuilder.conjunction();

            Long id = releaseRequestSearchInput.getId();

            if (id != -1) {
                predicate = criteriaBuilder.and(predicate, criteriaBuilder.equal(root.get("relReqK"), id));
            }

            if (StringUtils.isNoneEmpty(releaseRequestSearchInput.getModuleTypeCode())) {
                predicate = criteriaBuilder.and(predicate, criteriaBuilder.like(root.get("moduleType").get("moduleTypC"), "%" + releaseRequestSearchInput.getModuleTypeCode() + "%"));
            }

            if (StringUtils.isNoneEmpty(releaseRequestSearchInput.getCalibrationLevel())) {
                predicate = criteriaBuilder.and(predicate, criteriaBuilder.like(root.get("calRLevelR"), "%" + releaseRequestSearchInput.getCalibrationLevel() + "%"));
            }

            if (StringUtils.isNoneEmpty(releaseRequestSearchInput.getStatus())) {
                predicate = criteriaBuilder.and(predicate, criteriaBuilder.like(root.get("statusC"), "%" + releaseRequestSearchInput.getStatus() + "%"));
            }

            if (StringUtils.isNoneEmpty(releaseRequestSearchInput.getOwner())) {
                predicate = criteriaBuilder.and(predicate, criteriaBuilder.like(root.get("createUserC"), "%" + releaseRequestSearchInput.getOwner() + "%"));
            }

            String modelYear = releaseRequestSearchInput.getModelYear();
            String program = releaseRequestSearchInput.getProgram();
            String engine = releaseRequestSearchInput.getEngine();

            // Subquery for WPCMS01_PGM_DESC based on modelYear, program, and engine
            if (!StringUtils.isBlank(modelYear) || !StringUtils.isBlank(program) || !StringUtils.isBlank(engine)) {
                // Create a subquery for the PGM_RELEASE_REQUEST table
                assert query != null;
                Subquery<Long> subquery = query.subquery(Long.class);
                Root<PgmReleaseRequest> subRoot = subquery.from(PgmReleaseRequest.class);
                subquery.select(subRoot.get("releaseRequest").get("relReqK"));

                // Join with ProgramDescription (WPCMS01_PGM_DESC)
                Join<PgmReleaseRequest, ProgramDescription> join = subRoot.join("programDescription");

                Predicate subPredicate = criteriaBuilder.conjunction();

                // Check for modelYear
                if (!StringUtils.isBlank(modelYear)) {
                    subPredicate = criteriaBuilder.and(subPredicate, criteriaBuilder.like(join.get("mdlYrR"), "%" + modelYear + "%"));
                }

                // Check for program
                if (!StringUtils.isBlank(program)) {
                    subPredicate = criteriaBuilder.and(subPredicate, criteriaBuilder.like(join.get("pgmN"), "%" + program + "%"));
                }

                // Check for engine
                if (!StringUtils.isBlank(engine)) {
                    subPredicate = criteriaBuilder.and(subPredicate, criteriaBuilder.like(join.get("engN"), "%" + engine + "%"));
                }

                subquery.where(subPredicate);
                predicate = criteriaBuilder.and(predicate, root.get("relReqK").in(subquery));
            }


            return predicate;
        };
    }

    private List<FirmwareResponse> convertToFirmwareResponse(List<FirmwareDto> firmwareDtos) {
        return firmwareDtos.stream()
                .map(firmwareDto -> new FirmwareResponse(firmwareDto.getPartR(),
                        firmwareDto.getCalibPartR(),
                        firmwareDto.getCatchWordC(),
                        firmwareDto.getEngineerCdsidC(),
                        NoticeFormatterUtility.formatWersNotice(firmwareDto.getWersNtcR()),
                        firmwareDto.getRelUsgX(),
                        firmwareDto.getHardwarePartR(),
                        firmwareDto.getCoreHardwarePartR(),
                        firmwareDto.getMicroTypX(),
                        firmwareDto.getSuplX(),
                        firmwareDto.getCoreHardwareCdsidC(),
                        firmwareDto.getStratCalibPartR(),
                        firmwareDto.getStratRelC(),
                        firmwareDto.getChipD(),
                        firmwareDto.getPwrtrnCalibCdsidC(),
                        programDescriptionRepository.fetchProgramDescriptionByPartNumber(firmwareDto.getPartR()),
                        firmwareDto.getPartNumX(),
                        groupFirmwares(partFirmwareRepository.fetchPartFirmwareByPartNumber(firmwareDto.getPartR())),
                        firmwareDto.getRelTypX(),
                        firmwareDto.getConcernC(),
                        firmwareDto.getCmtX())).toList();
    }


    private List<GroupedFirmwareResponse> groupFirmwares(List<LookupPartFirmwareDto> firmwares) {
        Map<String, List<LookupPartFirmwareDto>> grouped = firmwares.stream()
                .collect(Collectors.groupingBy(LookupPartFirmwareDto::getFirmwareCatgN));

        return grouped.entrySet().stream()
                .map(entry -> {
                    GroupedFirmwareResponse groupedResponse = new GroupedFirmwareResponse();
                    groupedResponse.setCategory(entry.getKey());
                    groupedResponse.setFirmwares(entry.getValue());
                    return groupedResponse;
                })
                .collect(Collectors.toList());
    }


    private String wersTable(List<WersTextPartDescriptionDto> descriptions, String relTypeCode) {
        StringBuilder strHtm = new StringBuilder();
        List<String[]> tableRows = new ArrayList<>();

        for (WersTextPartDescriptionDto desc : descriptions) {
            // Create an array for each row
            tableRows.add(new String[]{String.valueOf(desc.getPgmK()), desc.getMdlYrR(), desc.getPgmN(), desc.getPlatN(), desc.getEngN(), desc.getTransN()});
        }

        // Process table rows
        for (String[] row : tableRows) {
            for (String cell : row) {
                strHtm.append(cell).append("  ");
            }
            strHtm.setLength(strHtm.length() - 2); // Remove last two spaces
            strHtm.append("<br>");
        }

        return strHtm.toString();
    }

    private String generateLineageTable(List<WersTextPartCalibDto> parts) {
        StringBuilder strHtm = new StringBuilder();
        String[][] aryTable = new String[parts.size() + 1][7];

        // Set header
        aryTable[0][0] = "LINEAGE";
        aryTable[0][1] = "OLD CAL";
        aryTable[0][2] = "OLD PN---";
        aryTable[0][3] = "OLD CW";
        aryTable[0][4] = "NEW CAL";
        aryTable[0][5] = "NEW PN---";
        aryTable[0][6] = "NEW CW";

        for (int i = 0; i < parts.size(); i++) {
            WersTextPartCalibDto part = parts.get(i);
            aryTable[i + 1][0] = part.getPartNumX();

            aryTable[i + 1][1] = (part.getOldCal() == null || part.getOldCal().isEmpty()) ? "N/A" : part.getOldCal();
            aryTable[i + 1][2] = (part.getReplacedPartR() == null || part.getReplacedPartR().isEmpty()) ? "N/A" : part.getReplacedPartR();
            aryTable[i + 1][3] = (part.getOldCw() == null || part.getOldCw().isEmpty()) ? "N/A" : part.getOldCw();
            aryTable[i + 1][4] = (part.getCalibR() == null || part.getCalibR().isEmpty()) ? "N/A" : part.getCalibR();

            if ("NewPnRequest".equals(part.getStatC())) {
                aryTable[i + 1][5] = "TBD";
                aryTable[i + 1][6] = "TBD";
            } else {
                aryTable[i + 1][5] = part.getPartR();
                aryTable[i + 1][6] = part.getCatchwordC();
            }
        }

        // Generate HTML for lineage table
        for (String[] row : aryTable) {
            for (String cell : row) {
                strHtm.append(cell).append("  ");
            }
            strHtm.setLength(strHtm.length() - 2); // Remove last two spaces
            strHtm.append("<br>");
        }

        return strHtm.toString();
    }

    private String getDisplayValue(String code) {
        // Mocked method; replace with actual logic to fetch display values based on code
        return code != null ? code : "Unknown";
    }

    private String wordWrap(String text, int width, String breakChars, String lineBreak) {
        String[] words = text.split(" ");
        StringBuilder wrappedText = new StringBuilder();
        StringBuilder line = new StringBuilder();

        for (String word : words) {
            if (line.length() + word.length() > width) {
                wrappedText.append(line).append(lineBreak);
                line.setLength(0); // Reset line
            }
            line.append(word).append(" ");
        }
        wrappedText.append(line); // Append remaining words

        return wrappedText.toString().trim();
    }


}
