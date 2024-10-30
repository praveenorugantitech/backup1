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

        // Sort by concern number, map results to PartNumberSearchResponse, and limit to 499
        return groupedByConcernNumber.entrySet().stream()
                .sorted(Map.Entry.comparingByKey()) // Sort by key (concernNumber) in ascending order
                .map(entry -> new PartNumberSearchResponse(
                        entry.getKey(),
                        entry.getValue()
                ))
                .limit(499) // Limit to 499
                .toList();
